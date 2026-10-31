# Asynchronous tasks and loop-owned channels: research spike

> Status: active - plan prepared; spike execution has not started.
> Requested 2026-10-30. This request commissions the plan, not execution.
> Baseline: the delivered global-lock work at `b75c61da9`, or a newer dev
> revision with its relevant changes recorded before comparison.
> Outcome: evidence and a recommendation on asynchronous tasks and later
> `async`/`await` support. No production runtime or language change is selected.

## Question and intended result

Can many waiting clients share one native event-loop thread, communicating
through channels without channel mutexes, while preserving message ownership,
cancellation, and cleanup? Does that improve a useful request/reply workload
enough to justify asynchronous task support in x2c?

The committed lock changes improved independent native-thread Pools and
Channels. They did not introduce suspended tasks or asynchronous functions.
Keep those improvements as the baseline. Do not reopen Pool index reclamation
or treat accepted historical regressions as new work in this spike.

Distinguish three claims throughout the report:

- A loop-owned queue needs no mutex because only its executor mutates it.
- Communication across native threads still needs coordinated publication
  and wakeup, whether implemented with locks or atomics.
- Asynchronous I/O avoids blocking the caller; it does not establish that
  its implementation, allocator, or operating system is lock-free.

## Scope and experimental choices

Use [channel-service.x](../examples/power/channel-service.x) as the working
request/reply example. Reuse the [libuv adapter](../packages/libuv/README.md)
for an event loop, timers, I/O, and cross-thread wakeup where applicable.

Build one scratch executor with explicit resumable functions and persistent
task records. Tasks stay on its native thread. Use ordinary queues whose
mutation cannot suspend or invoke reentrant user code. A readiness callback
schedules a task; it does not recursively run arbitrary task continuations.

For the experiment, starting a task enqueues its first resume. The enclosing
service run owns task records and joins their completion before destruction.
Each task has at most one outstanding channel operation. Cancellation is
cooperative and local to that task. These are prototype choices, not proposed
public language semantics.

Preserve these existing Channel contracts in the experimental operations:

- Non-void messages; closed and drained reception reports exhaustion.
- Bounded capacity and capacity-zero rendezvous.
- Acceptance is distinct from completed processing.
- Cancellation before commitment prevents the operation; commitment survives
  later cancellation. Cancellation does not implicitly close the channel.
- Borrowed payloads remain borrowed. Explicit ownership handoff transfers
  cleanup responsibility at acceptance and restores it on failed send.
- Every user and pending operation finishes before channel storage expires.

Use existing detached storage movement for owned payloads. Do not introduce
implicit object-graph copying or a global allocation lock.

Do not implement syntax, compiler lowering, task migration, work stealing,
general multi-producer lock-free queues, or a replacement for ordinary
Thread/Channel. Do not add recurring gates or benchmark requirements.
Any unavoidable production change becomes a reported design question, not
an incidental part of the prototype.

## Experiment sequence

### 1. Freeze the comparison and predict costs

Record the baseline revision, source, build flags, platform, and libuv version.
This planning checkout predates the delivered lock work; do not benchmark its
current Channel as the new baseline. Prepare isolated scratch work from the
selected delivered revision using the repository's normal bootstrap setup.

Before coding, trace one complete request/reply through each proposed model.
Count queue operations, mutex/atomic operations, allocations, native wakeups,
task resumes, and storage retained per waiting client. Separate immediate
completion from waiting, and single-client from many-client behavior.

State which costs disappear and which replace them. Where a cost is unknown,
name the measurement that will resolve it. Do not predict a universal speedup
from removing a mutex. In particular, an uncontended call has no lock-wait
cost to recover, and one event loop does not provide CPU parallelism.

### 2. Establish task lifetime feasibility

Implement two interleaved resumable tasks and one loop-owned channel before
building the workload matrix. Exercise a local value that survives suspension,
independent allocation owners, and completion/failure cleanup.

Inspect the existing owners before deciding what task state must persist:
[Scope regions](../lib/scope/regions.x), [Context](../lib/context.x),
[Error runtime](../lib/error/runtime.x), [Exception](../lib/exception.x),
and [try lowering](../src/components/try-catch.x).

The current exception landing is a C-stack `sigsetjmp` frame. It cannot remain
active after its invocation returns. Each resume may use ordinary synchronous
exception handling, but an error crossing suspension must live in explicit
task state. Persistent cleanup obligations must likewise outlive the resume
invocation and execute once on completion, failure, or cancellation.

Use existing Scope operations to establish and restore allocation context
around each resume. Identify other task-visible state that needs restoration;
do not blindly copy all thread-local storage. Record any Context or Error
behavior the explicit prototype cannot faithfully represent.

Force cancellation on both sides of message commitment. Verify borrowed data
remains live until actual use finishes, accepted owned data survives sender
completion, and failed sends restore ownership. Include close with pending
senders/receivers and receiver failure after ownership transfer.

If these semantics cannot be represented without a material runtime change,
report the exact obstacle and stop dependent work. A restricted successful
prototype must not be described as proof of general async-function support.

### 3. Compare one service under increasing concurrency

Implement the same checked request/reply transformation in two forms:

1. Native clients and service using the committed Thread/Channel runtime.
2. Resumable clients and service using the scratch executor and local channels.

Use identical payloads, transformations, response checks, queue capacities,
and ownership modes. Start with integer messages, then an owned Map or Array.
Run immediate replies first. Add controlled waiting using a fixed delay with
native sleeping in the threaded version and a timer in the loop version.
Timer results establish waiting-task behavior, not real-I/O throughput.

Use 1, 8, and 64 concurrent clients, with one outstanding request per client.
Test rendezvous and capacity 64. Increase to 256 clients only when the smaller
runs are informative and host resources permit it. Record resource limits;
do not silently reduce one variant's work or extrapolate failed runs.

Separate service startup/teardown, steady-state requests, and idle waiting
footprint. Equalize live clients and payloads at memory sampling points.
For the initial transport comparison, keep request count fixed across variants.

If the basic experiment remains promising, add one bounded loopback socket
request/reply case against the same service behavior. Compare native blocking
I/O with the libuv path, using identical framing, bytes, and request counts.
Keep that result separate from pure in-memory channel costs.

Finally, exercise one native worker returning a result to the loop. Reuse a
simple synchronized inbox and coalescing wakeup first; no new lock-free queue
is required. Drain published messages on notification. Do not equate wakeup
count with message count, assume the pinned libuv version publishes arbitrary
shared data, or block the loop by joining an unfinished worker. Keep the
inbox and wakeup handle alive until the worker has finished.

### 4. Measure and explain

Collect completed requests per second, median and p95 request latency,
process CPU time, elapsed time, native thread count, and live/peak memory.
Where available, collect instruction counts and allocations per request.
Define latency from submission to checked reply, including capacity waits.

Use warmup and at least five alternating baseline/prototype pairs with the
same toolchain and work. Serialize owned builds and measurements. Record host
conditions and raw samples. Keep diagnostic instrumentation separate from
acceptance timings; overlapping thread wait spans are not elapsed time.

Explain results against the initial cost prediction. Inspect generated code
when extra calls, spills, or allocation setup could explain unexpected costs.
Do not respond to an unexplained regression with another design iteration.
Profile it first. Limit this spike to the initial prototype and one measured,
mechanism-specific correction; otherwise report the remaining uncertainty.

## Decision and deliverables

Produce a dated report under `plans/reference/` with exact revisions, commands,
raw-evidence locations, cost predictions versus observations, semantic results,
and limitations. Keep scratch code and outputs outside shipped source, and
preserve enough evidence to reproduce the result before removing scratch work.

Recommend one of the following:

- Proceed to language design: lifetime/cancellation experiments pass, waiting
  clients show a repeatable useful CPU, memory, or latency benefit, and the
  remaining costs are explicit. This is not permission to accept tradeoffs.
- Keep callback/resumable support as a library direction: the runtime model
  helps, but language syntax is not yet justified.
- Stop or narrow the approach: no useful benefit appears, semantics require
  disproportionate machinery, or evidence remains insufficient.

Do not require this new model to beat threads on every workload. Report every
regression and seek Gary's decision before proposing production adoption with
tradeoffs. A failed prototype rejects that implementation and measured scope,
not every asynchronous execution model.

If language design is warranted, list the unresolved choices: eager/lazy start,
task and result ownership, borrowed arguments across suspension, Error transfer,
cancellation, defer/auto/finally, synchronous callers, and Thread interoperability.
Compare stackless lowering with stackful execution at the affected boundaries.
Do not select syntax or expand to migrating tasks in this spike.

Finish by reviewing the complete experimental source and report against these
questions. Remove unnecessary machinery and correct unsupported conclusions.
Then present the recommendation. No runtime publication is part of the spike.

## Plan review

Existing Channel contracts establish commitment, explicit payload ownership,
and quiescent destruction. Scope operations establish allocation ownership;
native thread-local exception frames establish synchronous cleanup only.
The prototype relies on those guarantees and does not add provenance checks
or graph validators. Suspension is the new boundary that needs investigation.

Reuse the service example, libuv adapter, and existing storage movement.
The scratch task record stores only continuation state, live values, pending
operation, and cleanup obligations. The ready queue schedules resumption; the
channel queue stores messages or pending operations. These are separate needs,
not a general scheduler framework. No production code is deleted or replaced.

Explicit records and functions keep the experiment ordinary x2c. New public
validators and diagnostics: none. Scratch semantic probes protect against lost
wakeups, incorrect commitment outcomes, use-after-free, and duplicate cleanup.
They do not create permanent fixtures or recurring validation requirements.
