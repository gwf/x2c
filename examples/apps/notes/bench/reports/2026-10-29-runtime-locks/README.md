# Runtime lock mitigation

The runtime removes the synchronization selected in `plans/archive/runtime-lock-mitigation.md`.
Pool ownership, Channel commitment, Logger callbacks and descriptor registration retain their existing serialization. Public layouts and signatures are unchanged. Scope names remain enabled.

## Notes lookup comparison

M4 Max, 64 clients/workers, 1,000-note SQLite fixture, GET /api/notes/1. Five alternating rounds per binary; one-second warmup and five seconds timed. Before is `fa1cf22fee3d30e72df6939ef8ba36a60e133269`; after is code head `493f1a01c`. Allocation accounting is disabled on both sides. Both x2c variants use the same saved application objects and SQLite adapter/native archives. Go is the unchanged, hash-verified control from the original comparison. Access logging remains enabled.

| Server | Requests/s | CPU us/request | Total CPU s | CPU cores | p99 ms | Peak RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Database mutex, before | 25,431 | 61.85 | 10.08 | 1.65 | 18.757 | 12.17 |
| Database mutex, after | 24,751 | 62.79 | 10.02 | 1.64 | 19.156 | 11.95 |
| Database thread, before | 13,569 | 110.34 | 8.19 | 1.34 | 34.544 | 12.48 |
| Database thread, after | 12,061 | 80.23 | 5.95 | 0.98 | 41.509 | 12.62 |
| Go | 21,984 | 70.86 | 10.97 | 1.80 | 14.119 | 22.55 |

Each cell is a median of its own sample values. CPU and RSS cover the server lifetime, including startup, warmup and shutdown. CPU/request divides lifetime user+system CPU by warmup+timed requests. Latency is the common closed-loop client measurement. Total CPU seconds and throughput cover different intervals; CPU seconds alone are not work-normalized.

These samples do not establish a throughput gain. Another integration checkout ran builds and checks while system services also consumed CPU. Go ranged from 17,578 to 54,052 requests/s; database-thread before ranged from 7,509 to 46,084. The cause of each timing change was not isolated. All samples and run order remain in comparison.json; none were removed. The database-thread candidate used less CPU/request in every matched pair, but its median throughput was lower. The mutex result is small relative to the observed variation.

### Complete same-host repeat

The mixed first result triggered a full second 25-sample comparison. The repeat reverses round order and within-round order, preserving all five samples per binary. It uses identical binary and fixture hashes. No slow samples were removed or replaced. The repeat is retained separately in repeat-comparison.json.

| Server | Requests/s | CPU us/request | Total CPU s | CPU cores | p99 ms | Peak RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Database mutex, before | 67,311 | 42.90 | 17.38 | 2.86 | 3.801 | 11.06 |
| Database mutex, after | 67,675 | 42.64 | 17.34 | 2.85 | 3.725 | 11.20 |
| Database thread, before | 46,136 | 252.20 | 69.13 | 11.34 | 3.112 | 10.84 |
| Database thread, after | 79,389 | 55.62 | 26.45 | 4.34 | 0.972 | 11.44 |
| Go | 67,286 | 50.62 | 20.40 | 3.36 | 2.174 | 22.56 |

In the repeat, database-thread throughput rises from 46,136 to 79,389 requests/s (72.1%). CPU/request falls from 252.20 to 55.62 us (77.9%). Total server CPU falls from 69.13 to 26.45 seconds while completing more requests. All five pairs improve throughput and CPU/request.

The mutex variant is close to neutral: 67,311 versus 67,675 requests/s, and 42.90 versus 42.64 us/request. The first attempt's lower throughput medians do not repeat here. Timing alone did not isolate their cause; the observed background activity and large control variation limit interpretation.

The repeat supports the database-thread improvement for this workload. It does not establish an intrinsic language comparison, a stable lead over Go, or equivalent performance for other workloads. Other system activity remained possible; the host was not certified quiet. Each table entry remains an independent median.

## Operation counts and footprint

A temporary native probe counts pthread mutex acquisitions, recursive acquisitions, condition broadcasts, and malloc/calloc calls and requested bytes. It does not count CPU instructions, contention duration or all native allocator operations. Pool thread locking is enabled before measurement. Instrumentation is outside shipped sources. Results for accounting off and on are in operation-counts.json.

| Operation, accounting disabled | Before locks | After locks |
| --- | ---: | ---: |
| Pool malloc, 1,024 bytes | 2 | 1 |
| Initialized Pool retain | 2 | 0 |
| Unnamed Scope destruction | 1 | 0 |
| Named Scope name lookup | 1 | 0 |
| Filtered global log event | 2 | 1 |
| Logger construction | 2 | 1 |
| Unused Channel destruction | 2 | 0 |
| Descriptor frozen status | 1 | 0 |
| Empty Thread.run batch | 1 | 0 |
| Listener stop | 1 | 0 |
| Stopped listener poll | 1 | 0 |

The filtered global event loses its recursive acquisition. HTTP uses instance logging, so this global-wrapper count does not measure its access-log savings. With accounting enabled, the large Pool request retains both acquisitions. All other listed reductions remain.

Buffered enqueue still broadcasts on empty-to-nonempty; dequeue still broadcasts on full-to-not-full. Nontransition enqueue/dequeue drop from one broadcast each to zero. Unused Channel destruction drops from one broadcast to zero. Rendezvous, close and Thread.stop broadcasts remain. No new waiter bookkeeping is added.

An unnamed Scope still requires one native allocation. Requested control bytes rise from 56 to 64; actual malloc_size remains 64 bytes for both versions on this Mac. Public sizeof(struct Scope) remains 56. This allocator observation is not a portable footprint guarantee. Logger/Pool constructions retain their allocation counts and add eight requested bytes for each included Scope record.

## Conditional stdio disposition

Retain the existing FILE locks. Four instrumented candidate runs measured 170-214 ns/request summed inside explicit flockfile/funlockfile calls, including timestamp overhead and any waiting. This is 0.25-0.39% of server lifetime CPU; it is not a subtractable isolated CPU measurement. Each run uses the same 64-client lookup, warmup and duration. stdio-profile.json retains the per-thread counters, timing sums and workload samples. Implicit stdio locks remain outside this count.

The remaining profile does not attribute a meaningful server CPU cost to the explicit line locks. No second parser, exclusive-input entry, public flag or File semantic change is introduced. The measurement does not establish that the calls have zero cost.

## Verification and delivery

- Combined accounting-on checks: 197 tests, 1,741 assertions passed. Accounting-off: 176 tests, 1,573 assertions passed. Scope counter-specific suite runs enabled; off-mode Scope behavior is covered by lifecycle probes.
- Existing Scope and Error lifecycle probes passed, including minimal Scope/thread-state preinitialization linking. Temporary native failure injection covers record, registry-node and copied-name failures, cleanup and successful retry, with accounting off/on.
- Both before/after Notes variants pass API, concurrency, restart, CLI/store compatibility tests. Database-thread SQL-error recovery and queued shutdown pass. All five server binaries return identical normalized fixture responses.
- Channel service and word-count examples match checked-in outputs.
- Public Scope and Pool generated headers compare byte-for-byte with baseline. Generated C confirms the atomic accesses and private wait_any removal. Independent cross-reviews found no remaining concrete defect.
- Author make stage-2 passed on code head 493f1a01c. No local rebootstrap was needed because compiler capabilities are unchanged. No full publication gate ran in this session.

Focused concurrency tests do not enumerate every scheduling interleaving. Pool initialization shutdown-hook allocation failure was not fault-injected. The shared integrator owns final bootstrap/document generation, the full publication gate, compiler performance checkpoint and publication.

## Retained evidence

Raw binaries, archives, application objects, fixture, logs and profiler CSVs remain in `/tmp/x2c-runtime-locks-nwm1p4m9`. Binary/source/fixture hashes and exact candidate link commands are recorded in both comparison files. The archive comparison confirms that only the eight intended runtime objects changed. Worker and parent validation log paths are in verification.json. The temporary drivers and probe sources remain in `.context/runtime-locks/` and are copied to the scratch directory; no profiler or benchmark framework is shipped.

Reproduction uses the existing Notes compare.measure implementation. Build normal runtime archives at the recorded baseline and candidate, compile each application object once with -O2, link the same objects against each runtime, pass the external tests and fixture preflight, and execute the recorded order with the common load client. Keep names enabled, unset X2C_SCOPE_ACCOUNTING, and retain every sample.
