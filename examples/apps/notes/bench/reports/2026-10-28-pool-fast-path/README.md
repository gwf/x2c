# Pool allocation fast path: 64-client lookup

Measured on 2026-10-28 on the same M4 Max host. Three rotated rounds per
binary, one second of warmup and five seconds timed, 64 clients, 1,000 notes,
GET /api/notes/1, common load generator and copied SQLite fixture.

| Server | Median requests/s | p50 ms | p99 ms | Server CPU cores |
| --- | ---: | ---: | ---: | ---: |
| x2c mutex before | 55,888 | 1.110 | 4.377 | 3.06 |
| x2c mutex after | 60,980 | 1.014 | 4.485 | 3.08 |
| x2c database thread before | 50,260 | 1.241 | 1.799 | 4.38 |
| x2c database thread after | 67,630 | 0.936 | 1.212 | 4.49 |
| Go | 66,268 | 1.077 | 2.223 | 3.39 |

Mutex Notes improves from 55,888 to 60,980 requests/s (9.1%). Database-thread
Notes improves from 50,260 to 67,630 requests/s (34.6%). Its median is 2.1%
above Go in this run; three short rounds do not establish a reliable lead.
The database-thread version still consumes more CPU than either mutex Notes
or Go. CPU cores are lifetime CPU seconds / lifetime elapsed seconds, including
warmup and startup; they are not timed-region CPU measurements.

Both x2c variants have name-registry work disabled using the same previously
built private Scope object. Allocation accounting is disabled. This is a
controlled runtime comparison, not a claim that the complete current shipped
runtime has naming disabled. The same application objects, SQLite adapter,
SQLite native archive, load generator, and fixture are retained.
Only pool.o differs between the two runtime archives (apart from their symbol
index). Hashes, order, individual samples, CPU usage, RSS, and host load are
in comparison.json. The saved reproduction script records the exact local
artifact paths; these temporary build artifacts are required to rerun it.

The change takes an existing slot under the owning Pool mutex without taking
the global storage mutex. A miss enters the existing global refill path after
releasing the Pool mutex. Per-allocation Pool traffic counters now honor the
existing X2C_SCOPE_ACCOUNTING opt-in; block/depot counters remain available.
Therefore this comparison includes disabling those traffic counters as needed
to remove their global synchronization. Accounting-enabled allocation keeps
the original globally locked path.

The corresponding safety changes lock the actual block owner on free, lock
the parent throughout block transfer, and synchronize block.used reads with
the owner. No API or structure layout changes, refill thread, or new locking
toggle were introduced. The Pool still locks internally around its metadata;
returned storage is used outside that lock under its lifetime contract.

Verification: 95 focused tests / 869 assertions with accounting enabled;
35 tests / 470 assertions with accounting unset. Both rebuilt Notes binaries
pass API, concurrent access, restart, CLI, and store compatibility checks.
Database-thread Notes also passes SQL error recovery and shutdown with queued
writes. An independent read-only review found no new locking defect.
