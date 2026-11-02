# Async tasks and loop-owned channels: spike results

> Status: reference - noted 2026-11-01. The design that followed this spike
> was published to `dev` in `255de641f` on 2026-10-31; the "local research
> only" and no-push statements below are historical.
> Design succession: [execution stacks](../archive/async-execution-stacks.md) records
> the subsequent semantic model. This report remains experimental evidence;
> private task allocation Scopes are not selected language semantics.

**Recommendation: proceed to language design for executor-bound tasks.**
The explicit lifetime probes pass. With 64 waiting owned-Array clients,
execution CPU is 0.035361 seconds native and 0.017527 seconds loop per 512
requests; blocked-client RSS is 3.219 MiB and 1.781 MiB respectively.
The report records allocation, memory, latency, and instruction tradeoffs.
No production adoption decision is made here.

Date: 2026-10-30. Local research only; no production runtime or compiler
change, publication gate, remote branch update, or syntax selection.

## Experiment and baseline

The baseline is `1355503543801f6565150a00c779668ab1d2d1bb`, which contains
`b75c61da9`. The intervening commits change SymbolSet literal syntax and add
this spike plan. Channel, Thread, Scope, Context, Exception, and the libuv
adapter have no intervening source changes. Both variants use this compiler
and runtime. No historical performance regression was reopened.

An isolated clone lives at `/tmp/x2c-async-spike-20261030`. The retained
sources, scripts, raw results, generated C, and logs are identified below.
The original worktree's production sources and generated artifacts are
unchanged.

The host is an Apple M4 Max with 128 GiB RAM, Darwin 24.6.0, build 24G830.
The native compiler is Apple clang 17.0.0, arm64. The compiler/runtime and
scratch executables use `-O2`. The adapter links pinned static libuv 1.52.1;
its source digest is
`66d511b9e6e334c0e62279eb234fbfb2b3110b1479c09b95b44c7afca8cff9e7`.
The executable links only libSystem dynamically. Native thread stacks are
8 MiB each. The reported process limit was 10,666 and descriptor limit
1,048,575. The power tool reported no recorded thermal or performance
warning. This was an interactive Mac, without exclusive host control.

## What was built

The request/reply transformation is `n -> n * 3 + 1`. Each client has one
outstanding request and checks every reply. Requests encode their client
number, avoiding extra request-envelope allocation. Both variants use either
inline integers or an owned one-element Array containing that integer.

The native variant uses the delivered Thread and Channel implementations.
The prototype uses ordinary x2c functions and explicit task records. One
native thread owns its ready queue, pending operation queues, and channel
rings. Completing an operation enqueues a continuation; it never calls that
continuation recursively. Starting a task enqueues its first invocation.

Both services process requests sequentially. The delay case waits once per
request: `nanosleep` in the native service and a one-shot libuv timer in the
loop service. It does not add concurrent service execution. Timer callbacks
only schedule the service. Timer wrapper storage belongs to the enclosing
run until libuv has completed handle closure.

There are no channel mutexes in the loop prototype because only that loop
thread changes the queues. Cross-thread publication still needs coordination.
The separate worker experiment uses a mutex-protected inbox and UvAsync
notification. Asynchronous I/O does not establish a lock-free allocator,
operating system, or libuv implementation.

## Lifetime and semantic evidence

Each task keeps its continuation position, live values, one pending operation,
and allocation Scope in a persistent record. Each resume pushes that Scope
and restores the previous allocation slot before returning. Completion,
cancellation, and caught failure destroy the task Scope after popping it.
Failure cause and copied detail have a separate explicit owner.

The main semantic probe reports nine owned-content finalizers and verifies:

- Interleaved persistent values use independent task allocation owners.
- A pending rendezvous send restores the Array and contents owners when
  canceled. Canceling a pending receive leaves its channel open.
- Accepted owned storage survives sender completion and destruction.
- Cancellation after commitment preserves the accepted operation.
- A receiver failure reclaims adopted storage exactly once.
- Close fails pending senders, exhausts pending receivers, and permits
  accepted buffered values to drain.
- A sender behind a full buffer restores ownership on cancellation or close.
- Channel destruction reclaims accepted owned values left undrained.
- Borrowed Array storage remains sender-owned through actual receiver use.
- The executor finalizes a failed task and a canceled task once. Copied
  failure detail remains available after another task executes.

An additional semantic-only executable extends that probe to eleven
finalizers. It verifies executor cancellation after committed send and receive,
including adopted cleanup, and distinguishes accepted null from exhaustion.

The scratch owned operations reuse detached storage movement, not graph
copying. An early probe incorrectly put a boxed `long` in an Array without
adopting the box. Sender destruction exposed the borrowed box. The final
workload uses inline `int`, as specified. This correction preserves the
existing ownership contract; it does not make arbitrary graphs transferable.

Review also found an unnecessary empty contents Scope in the prototype's
owned preparation. The final implementation preserves nullable
`Block.lifetime`, matching native Channel. A delay sweep exposed timer storage
that expired before its libuv close callback; the final run owner fixes that
lifetime. Preliminary samples are retained separately and excluded from
acceptance results.

This is evidence for restricted explicit resumable functions. It is not proof
that arbitrary existing functions can suspend. C locals and exception frames
cannot survive return. The relevant current owners are:

- `lib/scope/regions.x`: push/pop, inactive Scope storage, and transfer.
- `lib/channel.x`: commitment, borrowed messages, and owned rollback/adoption.
- `lib/exception.x` and `src/components/try-catch.x`: C-stack exception
  landings and borrowed cleanup environments.
- `lib/context.x`: LIFO current Context with Scope, Error, Match, and optional
  Pool state. There is no Context detach/reactivate operation.
- `lib/error/records.x`: explicit-owner Error snapshots.

The prototype shares the enclosing canonical Pool. It does not preserve
independent task Context nesting, Error policy overlays or observers, Match
leases, private Pool ownership, or compiler-generated defer/finally regions
across suspension. Those require design decisions before implementation.

## Predicted and observed costs

The original prediction is retained in `prediction.md`, written before the
prototype. Each checked request requires two sends and two receives in both
variants. Native buffering allocates two native queue nodes per request;
rendezvous uses existing thread-local wait records. Native operations retain
queue mutexes, cooperative-stop publication, condition waits, and native
scheduling when blocked. Their dynamic counts were not instrumented, so no
claim assigns all measured CPU savings to mutex removal alone.

The loop replaces those native handoffs with ready-queue operations, explicit
continuation state, and allocation-context restoration. It has no per-message
native queue-node allocation. The observed continuation count is `7*N + 2`,
including startup and exhaustion, for both immediate and delayed replies.
The prediction counted four operation completions as a minimum. The other
three resumes are bookkeeping states in this implementation. The immediate
path already schedules the state that a timer schedules in the delayed path.

Generated C confirms a synchronous exception boundary around each resume,
including `sigsetjmp`, a cleanup registration, and an Error handler allocation.
This is a real replacement cost, not a zero-allocation scheduler. Task records
are 144 bytes. Local channels are 1,072 bytes because every channel reserves a
64-message ring, including rendezvous channels. A client therefore reserves
1,216 bytes for its task and reply-channel record, before Scope, payload, and
allocator storage. Reserved record bytes are not resident-memory measurements.

Owned Arrays move through two detached transport Scopes per request. Both
variants preserve borrowed references inside containers. The prototype does
not copy a message graph, add a shared allocator lock, migrate tasks, or
supply CPU parallelism.

No performance optimization iteration was selected. Changes during the spike
corrected the scratch program's ownership, timer lifetime, and measurement
boundaries. Preliminary samples do not establish a causal performance effect
for any individual correction.

## Measurement method

The in-memory matrix uses 1, 8, and 64 clients; capacities zero and 64; integer
and owned-Array messages; and immediate and nominal 1 ms delayed replies.
Each immediate sample completes 65,536 requests. Each delayed sample completes
512. The count is identical between the native and loop variants in each
comparison and divides evenly among clients.

Each cell has a discarded warmup of each variant, followed by five pairs.
The first pair runs native then loop, and successive pairs alternate order.
Every sample runs in a fresh process. Warmup primes host code/data pages; it
does not preserve an allocator or runtime cache between measured processes.
Builds and measurements were serialized. Diagnostic accounting and sanitizer
runs are separate from acceptance timings.

Latency starts before request construction and ends after reply validation.
It includes channel capacity waits. The per-run median is the upper middle
sample; p95 is the sorted sample at integer index `N*95/100`. Table entries
are medians of five complete runs, not pooled request distributions.
Startup, execution, and teardown have separate timestamps. Native execution
includes consuming joins and worker runtime teardown. Loop execution includes
task Scope destruction; libuv handle draining belongs to teardown. These
phases are useful measurements, not an assertion of identical internal steps.

CPU is process user plus system time during execution. The raw data also
retain whole-process CPU, startup-ready RSS, peak RSS, native thread counts,
and `/usr/bin/time -l` instruction, cycle, and peak-footprint counters.
Hardware counters cover the whole process, including startup and latency
sorting. They are not transport-only instruction counts. macOS supplied these
counters; no privileged tracing or host configuration change was needed.

The final delay branch adds exception-safe restoration around timer creation.
All delayed cells were remeasured. Immediate cells retain their earlier
samples because that branch is not executed. Their exact earlier combined
source is retained, and each acceptance sample records its source SHA-256.
The reproduction script runs the full matrix with the final source.

## Results and recommendation

For 64 clients, capacity 64, owned Arrays, and nominal 1 ms waiting, 512
requests used 0.035361 seconds of native CPU and 0.017527 seconds of loop CPU.
Loop CPU was lower in all five pairs: loop/native ratios ranged from 0.385
to 0.636. At the equal-live-payload memory sample, native RSS was 3.219 MiB
and loop RSS was 1.781 MiB, with 66 native threads versus one.

For eight clients with immediate owned-Array replies, capacity 64, and
65,536 requests, native CPU was 0.412325 seconds and loop CPU was 0.038455
seconds. Throughput was 499,269 versus 1,704,226 checked requests/second.
Every pair favored the loop on these two metrics. These workloads establish
a useful benefit; they do not establish a universal speedup.

### Complete in-memory matrix

CPU values cover the execution interval. Immediate rows use 65,536 requests;
delayed rows use 512. All numbers below are medians of five runs.

| Clients | Capacity | Payload | Delay ms | Native req/s | Loop req/s | Native CPU s | Loop CPU s | Native p95 ms | Loop p95 ms |
|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 0 | int | 0 | 194,932 | 2,452,511 | 0.3546 | 0.0267 | 0.007 | 0.001 |
| 1 | 0 | int | 1 | 648 | 786 | 0.0270 | 0.0172 | 1.614 | 1.365 |
| 1 | 0 | Array | 0 | 237,167 | 1,729,638 | 0.2802 | 0.0379 | 0.007 | 0.001 |
| 1 | 0 | Array | 1 | 649 | 793 | 0.0281 | 0.0168 | 1.614 | 1.359 |
| 1 | 64 | int | 0 | 192,590 | 2,371,142 | 0.3576 | 0.0276 | 0.007 | 0.001 |
| 1 | 64 | int | 1 | 649 | 788 | 0.0275 | 0.0162 | 1.612 | 1.356 |
| 1 | 64 | Array | 0 | 246,987 | 1,774,985 | 0.2676 | 0.0369 | 0.006 | 0.001 |
| 1 | 64 | Array | 1 | 645 | 791 | 0.0315 | 0.0163 | 1.626 | 1.363 |
| 8 | 0 | int | 0 | 58,470 | 2,403,051 | 4.2481 | 0.0273 | 0.168 | 0.004 |
| 8 | 0 | int | 1 | 655 | 793 | 0.0618 | 0.0163 | 12.545 | 10.695 |
| 8 | 0 | Array | 0 | 57,925 | 1,677,142 | 4.2998 | 0.0391 | 0.169 | 0.005 |
| 8 | 0 | Array | 1 | 650 | 797 | 0.0678 | 0.0172 | 12.648 | 10.705 |
| 8 | 64 | int | 0 | 492,123 | 2,319,941 | 0.4199 | 0.0283 | 0.028 | 0.004 |
| 8 | 64 | int | 1 | 660 | 794 | 0.0222 | 0.0159 | 12.409 | 10.793 |
| 8 | 64 | Array | 0 | 499,269 | 1,704,226 | 0.4123 | 0.0385 | 0.027 | 0.005 |
| 8 | 64 | Array | 1 | 660 | 800 | 0.0258 | 0.0172 | 12.390 | 10.661 |
| 64 | 0 | int | 0 | 8,808 | 2,260,096 | 86.7394 | 0.0290 | 9.364 | 0.029 |
| 64 | 0 | int | 1 | 620 | 790 | 0.4570 | 0.0152 | 104.847 | 83.939 |
| 64 | 0 | Array | 0 | 8,743 | 1,657,838 | 87.7433 | 0.0395 | 9.483 | 0.040 |
| 64 | 0 | Array | 1 | 617 | 789 | 0.4547 | 0.0177 | 105.633 | 84.113 |
| 64 | 64 | int | 0 | 535,079 | 2,245,999 | 0.4110 | 0.0292 | 0.173 | 0.029 |
| 64 | 64 | int | 1 | 660 | 797 | 0.0340 | 0.0161 | 98.306 | 83.190 |
| 64 | 64 | Array | 0 | 511,752 | 1,631,141 | 0.4286 | 0.0402 | 0.164 | 0.041 |
| 64 | 64 | Array | 1 | 659 | 793 | 0.0354 | 0.0175 | 98.140 | 83.833 |

The large rendezvous cost at 64 clients belongs to the delivered native
baseline. The source broadcasts on its shared channel condition and
coordinates stopped waiters. Dynamic wakeup/lock counts were not collected,
so the report does not assign a precise fraction of CPU to those operations.
This spike neither repairs that baseline nor treats it as evidence against
native threads for CPU-parallel work.

### Blocked-client storage

Each footprint sample has exactly C constructed live payloads. The service
cannot consume any before sampling. Native clients report construction and
then enter their send; a 20 ms settling interval precedes sampling. That
interval does not mechanically prove every native client reached the wait
instruction. The loop has C explicitly pending sends. Both variants retain
C reply channels and a service record or thread.

| Clients | Payload | Native RSS MiB | Loop RSS MiB | Native threads | Loop threads |
|---:|---|---:|---:|---:|---:|
| 1 | int | 1.750 | 1.719 | 3 | 1 |
| 1 | Array | 1.766 | 1.719 | 3 | 1 |
| 8 | int | 2.125 | 1.734 | 10 | 1 |
| 8 | Array | 2.141 | 1.734 | 10 | 1 |
| 64 | int | 3.188 | 1.766 | 66 | 1 |
| 64 | Array | 3.219 | 1.781 | 66 | 1 |
| 256 | int | 7.047 | 2.078 | 258 | 1 |
| 256 | Array | 7.109 | 2.141 | 258 | 1 |

These are resident bytes, not stack reservations. A native worker reserves
8 MiB of virtual stack; most pages are not resident. The loop's reply rings
are mostly untouched at this sampling point. Their reserved record sizes
therefore must not be equated with RSS. Raw samples separately record
startup-ready zero-payload RSS and execution peak RSS.

### Extension to 256 clients

The 64-client results were informative and the host had sufficient resources,
so the extension used capacity 64 with the same request counts. No run was
reduced or extrapolated because of a resource failure.

| Payload | Delay ms | Native req/s | Loop req/s | Native CPU s | Loop CPU s | Native median ms | Loop median ms | Native p95 ms | Loop p95 ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| int | 0 | 23,918 | 2,306,956 | 38.3882 | 0.0284 | 5.779 | 0.111 | 35.299 | 0.120 |
| int | 1 | 708 | 870 | 1.0088 | 0.0121 | 199.248 | 291.582 | 574.542 | 296.636 |
| Array | 0 | 17,976 | 1,588,983 | 51.6583 | 0.0412 | 7.540 | 0.160 | 44.759 | 0.176 |
| Array | 1 | 712 | 873 | 1.2786 | 0.0144 | 210.120 | 291.377 | 552.841 | 294.415 |

The delayed extension regresses median latency. For owned Arrays, native
median latency is 210.120 ms and loop median latency is 291.377 ms; p95
changes from 552.841 ms to 294.415 ms. The integer case has the same tradeoff.
The loop serves pending senders in FIFO order. Native buffered Channel uses
condition/mutex competition without a pending-sender FIFO. Thus these
variants preserve the documented Channel contract but differ in admission
order. Fairness was not a stated compatibility guarantee.

A separate per-client diagnostic reproduces the distribution difference.
For owned Arrays, 57 native first requests waited over 400 ms; none of the
loop first requests did. Ninety native second requests finished within
150 ms; none of the loop second requests did. The loop's second round clusters
near 292 ms. This supports an admission-order explanation; it does not prove
that fairness is the sole cause. No scheduler revision followed this result.

### Bounded loopback TCP

Eight clients exchange four-byte network-order integers. Both variants send
the same 16,384 requests and validate `n * 3 + 1`. Native clients use blocking
reads/writes and one polling service thread. Libuv uses framed callbacks on
one loop thread. `TCP_NODELAY` is enabled on both endpoints in both variants.
Latency begins before frame preparation. A discarded warmup precedes five
alternating pairs.

| Metric | Native | Libuv loop |
|---|---:|---:|
| Checked requests/s | 189,073.788000 | 205,958.517000 |
| Execution CPU seconds | 0.207815 | 0.079550 |
| Median latency ms | 0.043000 | 0.039000 |
| p95 latency ms | 0.054000 | 0.042000 |
| Whole-process retired instructions | 1,081,935,939.000000 | 1,182,931,979.000000 |

The loop retires 1,182,931,979 instructions versus 1,081,935,939 native
instructions, a 9.3% regression. CPU changes from 0.207815 to 0.079550 seconds.
These are separate measurements; lower CPU does not mean fewer instructions.
One-second `sample` profiles, using a separate 1,048,576-request workload,
show libuv read/write callbacks, Bytes creation/freeing, payload copies, and
Error handler allocation. Native client stacks mainly show blocking reads;
the service polls and writes. The profiles identify replacement work but do
not assign the exact instruction delta to individual functions. Sampled
native waiting spans overlap and were not added into elapsed or CPU totals.
No adapter optimization was attempted.

This case measures the existing libuv callback path. It does not measure
async-function lowering or establish general network throughput.

### Native worker return

Five runs each publish 1,000 integers through a mutex-protected inbox and
call UvAsync.send for every publication. Each observed one callback, which
drained all 1,000 messages and checked sum 499,500. Coalescing is observed,
not assumed as a fixed callback count. Publication comes from the mutex,
not a claim that the pinned libuv version publishes arbitrary shared data.
The worker deliberately remains alive after its last notification. The loop
callback never joins it. Joining occurs after the loop run returns; inbox
and wakeup handle remain alive through that join.

### Allocation and teardown costs

Separate Scope-accounting runs at eight clients, capacity 64, and 4,096
immediate requests produced:

| Payload | Native Scope allocations | Loop Scope allocations | Native Scope creations | Loop Scope creations |
|---|---:|---:|---:|---:|
| int | 0 | 28,683 | 0 | 1 |
| owned Array | 8,192 | 36,875 | 8,192 | 8,202 |

The loop adds approximately seven handler allocations per request. These
counts exclude raw malloc calls, including native buffered queue nodes,
Scope records themselves, and libuv internals. They are not total allocator
call counts. Accounting timings are excluded from acceptance results.

Loop teardown is slower in all twelve delayed matrix cells. Native median
teardown ranges from 14 to 66 microseconds; loop medians range from 111 to
175 microseconds. Seven immediate one/eight-client cells also regress by
1-3 microseconds. Every raw timestamp is retained. The 64-client detail is:

| Payload | Delay | Native startup ms | Loop startup ms | Native teardown ms | Loop teardown ms |
|---|---:|---:|---:|---:|---:|
| int | 0 | 1.341 | 0.027 | 0.008 | 0.003 |
| int | 1 | 3.602 | 0.068 | 0.061 | 0.133 |
| Array | 0 | 1.686 | 0.027 | 0.008 | 0.006 |
| Array | 1 | 3.499 | 0.087 | 0.066 | 0.166 |

One-client delayed peak RSS also regresses in all four payload/capacity
cells. Native/loop medians, in bytes, are 1,867,776/2,146,304 for rendezvous
integers, 2,080,768/2,146,304 for rendezvous Arrays,
2,031,616/2,162,688 for buffered integers, and 2,048,000/2,129,920 for
buffered Arrays. The largest increase is 14.9%.

The timer prototype creates one Scope-backed wrapper per request and retains
those wrappers until the run ends. UvTimer.stop closes the handle but does not
free the wrapper's Scope allocation. Diagnostic managed-payload peaks for the
one-client rendezvous integer delay case are 34,960 native bytes and 121,392
loop bytes. This identifies a concrete retained-storage cost. Native allocator
pages and libuv internals are outside those counters, so they do not explain
every RSS byte. A production timer-storage strategy remains undecided.

No median execution CPU, throughput, or latency regression appeared in the
1/8/64 matrix. That observation is limited to these cells and this host.
The 256-client latency, TCP instructions, timer peak RSS, handler allocation,
and teardown costs above remain explicit tradeoffs. Production adoption
requires Gary's decision; the spike does not accept them on his behalf.

## Design boundaries for a subsequent decision

The evidence can justify a language-design discussion. It does not choose
syntax, authorize production tradeoffs, or establish general async semantics.
These choices remain open:

- Eager versus lazy task start and the owner of an unstarted task.
- Task/result ownership, joining, and destruction of unobserved results.
- Borrowed arguments and nested borrowed references across suspension.
- Durable Error data, task-specific policies, and propagation to awaiters.
- Cooperative cancellation, operation commitment, and cleanup after commitment.
- `defer`, `auto`, and `finally` obligations that span suspension.
- Calling asynchronous operations from synchronous code and blocking libraries.
- Native Thread interoperability, publication, wakeup, and shutdown ownership.

Stackless and stackful execution affect the same boundaries differently:

| Boundary | Stackless lowering | Stackful execution |
|---|---|---|
| Locals across suspension | Compiler stores live values and continuation state in a task record. | Retained native stack holds locals; each task needs stack storage and switching support. |
| Exception landings | A C invocation ends at suspension; Error transfer must use persistent task data. | Stack frames can remain allocated, but exception and cleanup TLS heads still need correct task switching. |
| Allocation and Context | Restore the task allocation slot at each resume; Context/Error/Match preservation needs an explicit contract. | Retaining a stack does not make the current thread's Scope or Context state task-local. Those owners still need a switching contract. |
| Cleanup | Lower suspension-spanning obligations into durable state and execute them once. | Existing stack cleanup records can remain stored, but cancellation and unwinding must target the correct task stack. |
| Memory | Keep task fields and live heap storage; generated field counts need measurement. | Reserve and commit stacks; stack size, growth, platform support, and switch cost need measurement. |
| Synchronous libraries | Calls that block the executor still block every task on that executor. | Retaining stacks alone does not convert blocking I/O into event-loop I/O. |
| Native workers | Coordinate publication and keep borrowed storage and notification handles alive. | The same cross-thread obligations remain. |

The controlled delay uses timers and sleep, so its throughput difference also
includes their wakeup and coalescing behavior on this Mac. Timer results are
not real-I/O throughput. The socket experiment is reported separately.

Neither model was implemented as a compiler feature. This spike cannot rank
their full compiler complexity, code size, performance, or portability costs.

## Scope and review

The source review checked queue commitment, ownership movement, pending
operation unlinking, task Scope restoration, deferred libuv handle closure,
framing, and synchronized inbox publication. The final source keeps one ready
queue and channel-specific message/wait queues. These serve separate lifetimes;
there is no scheduler framework, work stealing, or task migration.

Owned-payload coverage is limited to Array roots containing inline integers
and explicitly owned finalizer storage. Maps and custom typed roots were not
exercised. Private per-task canonical Pools and arbitrary Context/Error/Match
nesting across suspension were not implemented. The report makes no general
async-function or replacement-Channel claim for those paths.

No production API, ABI, compiler lowering, gate, recurring benchmark, Pool
reclamation rule, or shared allocator synchronization changed. No full
publication gate was run because no publication was requested. The report and
plan status remain local for review. Nothing was pushed to `dev`.

## Reproduction and retained evidence

The evidence copy is
the workspace-local, untracked `.context/async-spike-20261030/` in the
originating worktree. The full isolated checkout
is retained at `/tmp/x2c-async-spike-20261030`. Neither location was removed.
The evidence copy contains:

- `spike/experiment.x`, `main.x`, `network.x`, and `footprint.x`: experimental
  authoritative sources. Combined units are generated by concatenation because
  x2c static functions belong to their defining unit.
- `spike/combined-initial-acceptance.x`: exact immediate-matrix source.
  `spike/combined.x`: final semantic/delay source. Each main-matrix row records
  the appropriate source SHA-256.
- `spike/samples.jsonl`: the 240 accepted matrix samples, validated as five
  native/loop pairs in every cell. `samples-delay-final.jsonl` preserves the
  final 120 delayed samples separately.
- `spike/extension-256.jsonl`, `network-samples.jsonl`, and
  `footprints.jsonl`: 40 extension, 10 socket, and 80 footprint samples.
- `spike/worker.log`, `allocation-diagnostics.log`,
  `distribution-diagnostics.log`, and `latencies-256-*.csv`: separate semantic,
  allocation, inbox, and distribution evidence.
- `spike/prediction.md`, `host.txt`, `tables.md`, and the harness scripts.
- `spike/additional-semantic-combined.x`: the separate post-commit task
  cancellation and null/exhaustion probes.
- `debug/`: complete build logs, semantic/sanitizer output, and both native
  and loop socket profiles. `generated/` retains generated experimental C/H.
- `SHA256SUMS`: hashes of the retained evidence files.

To reproduce acceptance measurements, clone the baseline, copy the retained
`spike/` sources/scripts into that clone, then run `sh spike/reproduce.sh`.
That script runs the ordinary bootstrap setup, pinned libuv package build,
serialized `-O2` builds, semantic probes, full paired matrix, footprint,
256-client extension, socket comparison, and worker probes.

The actual setup/build commands were:

```sh
git clone --no-hardlinks . /tmp/x2c-async-spike-20261030
cd /tmp/x2c-async-spike-20261030
mkdir -p debug
make build-safe >debug/bootstrap.log 2>&1
make -C packages/libuv build >debug/libuv-build.log 2>&1
builds/0/x2c build --package-dir packages \
  --c-include-dir packages/libuv/deps/include -O2 \
  --build-dir spike/build --output spike/experiment spike/combined.x
spike/experiment semantics
python3 spike/run.py
python3 spike/run-extra.py
python3 spike/diagnostics.py
```

The final delay rerun used `python3 spike/run.py --delay-only`; the summary
script selects unchanged immediate cells and the final delayed cells.
Diagnostic distribution builds use `distribution-combined.x` with
`X2C_SCOPE_ACCOUNTING=1` and `ASYNC_SPIKE_LATENCIES` naming the CSV output.
The retained diagnostic source records request latency before sorting.

Sanitizer verification used `-O2 -g --cc spike/asan-cc` in a separate build
directory. The wrapper adds `-fsanitize=address` to the same system compiler.
The final semantic and 64-client delayed owned-Array probes passed. The
runtime and libuv static archives were not sanitizer-instrumented; this is
limited scratch-code coverage, not a fully instrumented runtime proof.
Scope-accounting semantic probes also passed without a named-scope leak
report. No permanent tests or recurring requirements were added.

Profiles ran `sample <owned-process-pid> 1 1 -file <profile-path>` while each
variant processed 1,048,576 socket requests. Those runs are diagnostic only.
Full bootstrap and package build logs, preliminary failures, and excluded
samples remain available. New authored Markdown passes ASCII and whitespace
checks. Publication validation and pushing were not attempted.
