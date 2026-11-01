# In-process Notes: Thread.run versus Task.run

Task.run improves concurrent Notes lookup throughput and CPU cost in this
workload. One client performs approximately the same in both modes.
This is an in-process request/reply result, not an HTTP result.

Measured local revision: `2636c4f9afac27faa83a46addf1f703ada3178a8`.
The tree was clean at measurement. Both modes use the same executable,
SQLite adapter, native SQLite 3.53.4 archive, and async-prototype runtime.
Thread.run is the comparison mode; this does not compare pre-async and
post-async runtimes. Ordinary synchronous regression evidence remains in
[the broader validation report](../../../../../../plans/reference/async-validation-2026-10-31.md).

## Results

Each value is the median of five five-second samples after one-second warmup.
Modes alternate order each round. CPU is process CPU, including database and
client work. Latencies below are medians of sample percentiles.

| Clients | Thread requests/s | Task requests/s | Thread CPU us/request | Task CPU us/request | Throughput change | CPU/request change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 56,209 | 55,748 | 17.760 | 17.811 | -0.8% | +0.3% |
| 8 | 122,381 | 156,240 | 19.279 | 12.506 | +27.7% | -35.1% |
| 64 | 120,761 | 157,296 | 20.512 | 12.509 | +30.3% | -39.0% |

| Clients | Thread p50 us | Task p50 us | Thread p99 us | Task p99 us | Thread peak RSS MiB | Task peak RSS MiB | Task usable stack capacity MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 18 | 18 | 27 | 24 | 8.20 | 8.14 | 8 |
| 8 | 65 | 49 | 91 | 72 | 15.23 | 20.52 | 64 |
| 64 | 521 | 399 | 695 | 544 | 19.27 | 24.08 | 512 |

All five pairs favor Task at 8 and 64 clients. At 8 clients, paired throughput
ratios range from 1.270 to 1.284 and CPU/request ratios from 0.638 to 0.651.
At 64 clients, those ranges are 1.283 to 1.327 and 0.593 to 0.632.
One-client differences are too small to establish an improvement.

Peak RSS is a lifetime high-water mark, including warmup, retained latency
samples, and the final sort buffer. Faster modes retain more samples, so RSS
does not isolate task stack residency. Task does not show a measured RSS
advantage here. Stack capacity is reserved virtual storage, not committed
physical memory. Each task also has one 16 KiB guard page on this host.
Native thread stack reservation was not measured.

## Work and measurement boundaries

The fixture contains 1,000 notes, created through the shared database worker.
Every sample starts with an independent copy. SQLite uses the ordinary DELETE
journal and FULL synchronous setting. Each client repeatedly looks up note 1
with the original prepared SELECT. The result contains six columns and encodes
to 103 JSON bytes, including parsed tags. Every response is checked against
the initial response before it counts as completed work.

One native thread owns SQLite. Clients communicate through request and reply
Channels. Thread mode has a native client thread per job; Task mode runs all
clients on the caller's executor. Both retain the native database thread.
Both modes create and release a request Scope and Pool for every operation.
They reuse one batch-owned request record, argument List, and buffered reply
Channel per client. The batch keeps borrowed storage alive until the database
queue drains and its thread joins, including cancellation.

Both modes parse tags, construct the note Map, encode JSON, and log each access
at info level to a separate regular stderr file. Per-request latency includes
allocation, Channel waits, SQLite, conversion, JSON, logging, and cleanup.
Recording the latency is outside that request's clock. Recording remains
inside timed batch CPU and wall time, as do batch launch and join.
Database opening, fixture preparation, warmup, and final sorting are outside
the timed interval. No HTTP parsing, sockets, or response writes are measured.

The shared database and JSON code was extracted from the existing
database-thread HTTP comparison server. Its API behavior remains covered by
the existing tests. No compiler or runtime implementation changed.

## Verification and provenance

- Existing Notes API, concurrency, restart, CLI, and incompatible-store tests passed.
- Existing database error-reply, recovery, and queued-shutdown checks passed.
- The final benchmark and all 81 runtime objects were freshly instrumented
  with ASan/UBSan. Twenty 64-client checks passed: five each for normal Thread,
  normal Task, failed Thread, and failed Task batches.
- Two additional instrumented failure checks passed with deliberately slow
  SQLite lookups and queued work. Stack-use-after-return detection was enabled;
  leak detection was disabled. SQLite and its adapter were not instrumented.
- The runner's normal/failure preflight and all 30 measured samples passed.
  Every normal sample reports native SQLite 3.53.4. The executable links the
  pinned SQLite archive, rather than macOS's system SQLite.

Application and adapter compilation used `-O2`; the same existing runtime
archive serves both modes. The host is macOS 15.7.9 arm64 on Apple M4 Max.
Another active benchmark chat received and later released a bounded quiet-window
request under Gary's existing authorization. No competing build or benchmark
appears in the process samples. Desktop, editor, and language-server activity
remained. These results are a local repeated comparison, not an idle-machine
calibration or evidence about other native targets.

[comparison.json](comparison.json) retains all sample values, order, fixture
configuration, source/compiler/runtime/SQLite/binary hashes, host loads, and
raw-log locations. [host-load.jsonl](host-load.jsonl) retains process samples.
Build and correctness logs are in the worktree's `debug/notes-inprocess-*`.
Sanitizer logs and binaries remain under `/tmp/x2c-notes-inprocess-2104`.
Per-sample access logs remain under `/tmp/notes-inprocess-26ffc1ga`.

The result supports Task.run for this concurrent Notes request/reply workload.
It does not establish HTTP throughput gains, a memory advantage, or acceptance
of the broader prototype's remaining regressions and publication checks.
Everything remains local. The dev/main validation and consent hold is unchanged.
