# Notes database ownership comparison, 2026-10-28

Allocation accounting is now opt-in through `X2C_SCOPE_ACCOUNTING=1`, latched
at Scope initialization. These measurements leave that variable unset, so
both x2c servers use the default disabled mode. This permanent implementation
also disables Scope lifetime and raw-backing counters; the earlier diagnostic
ablation disabled only three managed-allocation helpers. Compare variants
within this report rather than attributing differences from older runs solely
to the application architecture.

The ordinary Notes server keeps row acquisition and statement finalization
inside its database mutex, then checks for a missing row and constructs the
response Map outside it. The comparison executable gives one thread exclusive
ownership of opening, using, and closing SQLite. HTTP workers submit jobs to
one shared request Channel and wait on a per-request buffered reply Channel.
The database thread returns copied rows in caller-owned output storage.
HTTP workers construct Maps and encode JSON after the reply. There is no
application database mutex or response cache in that variant.

## Measurements

Five rounds used the same 1,000-note database fixture, 64 persistent clients,
one-second warmup, and five-second measurement per server. Execution order
varied by round. Every sample started a fresh server and independent fixture
copy. All requests succeeded. Access logging remained enabled. All three
executables passed the existing external Notes contract suite and produced
matching normalized lookup, list, stats, and update results before timing.

| Median | Mutex x2c | Database-thread x2c | Go |
| --- | ---: | ---: | ---: |
| Requests/second | 49,765 | 38,650 | 65,858 |
| p50 latency, microseconds | 1,246 | 1,596 | 1,082 |
| p99 latency, microseconds | 4,691 | 2,590 | 2,215 |
| Server CPU, cores | 3.23 | 7.71 | 3.42 |
| Peak RSS, MiB | 11.34 | 11.48 | 22.66 |
| Minimum requests/second | 48,445 | 38,323 | 63,001 |
| Maximum requests/second | 51,045 | 39,842 | 67,227 |

The database-thread variant has 22.3% lower median throughput than mutex x2c,
but its p99 latency is 44.8% lower. It loses throughput and improves p99 in
all five paired rounds. Its measured server CPU use is 2.38 times the mutex
variant. Go has higher throughput and lower p50/p99 than either x2c server
in this workload. Both x2c servers have lower observed peak RSS than Go.

These results support keeping the mutex implementation as the ordinary Notes
example while retaining the database-thread executable for comparison. They
do not establish that all database-owner or channel implementations have the
same performance. The database-thread variant was not CPU-profiled in this
run, so no particular queue, allocator, or scheduler is assigned the CPU cost.

## Controls and verification

Both x2c executables use the same optimized compiler, runtime archive, SQLite
adapter, and SQLite 3.53.4 native archive. Application C is compiled with -O2.
Go is the unchanged Go 1.27.3 optimized executable from the earlier comparison,
with Cgo -O2 -g and the same native SQLite archive. Native SQLite, adapter,
fixture, and Go hashes were checked against that comparison. There is one
SQLite connection in each application, DELETE journaling, FULL synchronization,
zero busy timeout, and the same schema and primary-key lookup SQL. Each request
prepares and finalizes its statement. No native library or durability setting
was changed for the database-thread variant.

The dedicated variant also passed focused SQL-error recovery and SIGTERM with
four outstanding writes. A private native fault-injection probe failed one
terminal reply allocation: the caller received HTTP 500, subsequent GET and
POST requests succeeded, and the process exited normally. Its failure handler
records the Error and closes the reply Channel to wake the caller.

The permanent Scope change passed focused enabled-accounting allocation and
ownership tests, default-off networking/HTTP tests, lifecycle probes in both
modes, selected compiler lifetime fixtures, real external-command environment
checks, REPL statistics, and LSP protocol/overlay tests. REPL/LSP launches
explicitly opt in because they consume the counters. ScopeStats layout,
allocation ownership, finalizers, names, and Pool storage policy are unchanged.
Disabled Scope statistics return zero and automatic Scope leak accounting is
disabled, as documented. Direct libexec/embedded users that require statistics
must set the environment before process startup.

## Interpretation limits and artifacts

CPU and peak RSS cover the server lifetime, including startup, warmup, and
shutdown. Client CPU covers the full load process, including sample sorting.
Latency values are medians of per-run closed-loop round-trip percentiles;
percentiles are not pooled. The servers and client ran on one shared Mac.
No worker builds or integrator gates ran during timing; unrelated host
processes were not stopped. Logging formatters differ between Go and x2c.
The matched ASCII workload does not remove the previously documented library
behavior differences for Unicode regular expressions, NUL, duplicate query
parameters, or redirects. No durable-write performance ranking is made.

- `comparison.json` retains every sample, order, host load, resources, source
  and binary hashes, and the temporary directory containing server logs.
- `verification.json` records build commands, compiler/runtime/native hashes,
  Scope source hashes, SQL configuration, and Go build metadata.
- `analysis.json` records paired throughput ratios and win counts.

No samples were discarded and no benchmark was added to a gate. Full final-tree
publication validation and generated bootstrap/documentation refresh belong to
the integration agent; this session ran focused checks only.
