# Shared-root index: 64-client lookup

Native String/List lookups in the process root now read an append-only index
without taking the root mutex. Root writes and custom equality remain under
the existing recursive mutex. Private Pools retain their existing tables.
The HTTP API, Notes application, database policy and channel implementation
are unchanged.

## Measurements

M4 Max, 64 clients/workers, 1,000-note SQLite fixture, GET /api/notes/1.
Three rounds per binary, one-second warmup and five seconds timed. Before is
the preserved runtime after the HTTP allocation cleanup. Naming and allocation
accounting are disabled in every x2c binary. Access logging remains enabled.
Every x2c binary linked an unshipped name-free Scope object; the
[complete same-host repeat](../2026-10-29-runtime-locks/README.md#complete-same-host-repeat)
in the 2026-10-29 runtime-locks report is the shipped-configuration
measurement.

| Server | Median requests/s | Server CPU cores | CPU us/request | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Database mutex, before | 65,941 | 2.79 | 43.26 | 4.406 |
| Database mutex, after | 68,805 | 2.80 | 41.46 | 3.743 |
| Database thread, before | 60,083 | 3.87 | 66.70 | 1.318 |
| Database thread, after | 79,441 | 4.14 | 53.01 | 1.053 |
| Go | 59,614 | 3.23 | 53.81 | 3.411 |

Database mutex: throughput increased 4.3%, and CPU per request decreased 4.2%.
Database thread: throughput increased 32.2%, and CPU per request decreased
20.5%. The database-thread server uses more total CPU cores while completing
more requests. Its CPU cost per request is now close to Go's in this run.
The database-mutex server still uses less CPU per request than either.

The host was not quiet: the integration agent continued repair builds and
other workspace activity was possible. All samples are retained. Database-thread
before had one 40,931 requests/s sample; its other samples were 60,083 and
60,732. All three after samples were 77,783-80,624. Go ranged from 59,576 to
68,752 requests/s. These measurements support improvement from removing the
root lookup lock, but do not establish a stable throughput lead over Go.

CPU cores divide server lifetime user+system CPU by lifetime elapsed time.
CPU/request divides the same CPU by warmup+timed requests, including startup
and shutdown. Each table cell is a median of its own per-sample measurements.
This is not timed-region-only CPU attribution. Server peak RSS medians remain
about 11-12 MiB for x2c, versus 22.8 MiB for Go; this small workload does not
measure retained index memory under a large, continuously growing root.

## Publication and ownership

Each bucket publishes its immutable value before its hash with release
ordering; readers acquire the table and hashes. Growth builds a replacement
in a staging Scope, transfers that Scope to the root, then publishes the table.
Allocation failure destroys the unpublished staging Scope. Older versions stay
owned by the root until quiescent shutdown. Geometric growth retains fewer
old buckets than the current table contains, plus table, Scope and Block records.
There are no reader counters or reclamation threads. Public layouts and
signatures are unchanged. Later root inserts and promotions remain supported.
String constructors consume the canonical identity returned by insertion so
competing constructors cannot return different equal root values.

## Controls and reproduction

An archive-member comparison verifies that only pool.o and string.o changed.
Both versions use identical saved application objects, SQLite adapter/archive,
HTTP/JSON runtime objects, naming-disabled Scope object, fixture and load
generator. Binary and fixture hashes, run order, CPU/RSS, latency and host
load are retained in comparison.json. Pair order changes between rounds;
three rounds cannot remove the host-load limitation.

prepare.py and run.py preserve the exact local preparation and measurement
commands. They depend on retained temporary application objects, baseline
archive and binaries. They are local reproduction scripts, not a standalone
benchmark harness. Scratch artifacts remain at the paths in comparison.json.

## Focused verification

- make build and make -C unittest test-all passed.
- Accounting-off Pool/HTTP/JSON/net suites: 51 tests, 709 assertions passed.
- Accounting-on Pool/Scope/Context/thread/ownership suites: 97 tests,
  892 assertions passed. The Pool suite alone passed 23 tests, 398 assertions.
- Both Notes API/concurrency/restart/CLI/store compatibility suites passed.
  Database-thread SQL error recovery and queued-write shutdown also passed.
- API audits passed: Pool 26 callables/3 types; String 88 callables/2 types.
- Root tests cover native reads while the root mutex is held, racing equal
  String inserts, promotions, retained values across growth, custom equality
  reentry that grows the index, and callback errors followed by successful use.
- Independent read-only reviews checked root access paths, publication,
  ownership, canonical identity and callback serialization.

The integration submission records author stage-2 evidence. The shared
integration agent owns generated artifacts, the full gate and publication.
