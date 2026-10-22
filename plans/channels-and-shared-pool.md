# Channels, ownership transfer, and the shared pool service

> Status: active design proposal, 2026-10-21.
> Requested design only; no runtime implementation or performance result.
> Source baseline: `e2a78078edece1348abbbb7363c89560ae064706`.
> This plan owns the proposed channel/thread/pool replacement described below.
> The saved tutorial remains the behavior baseline, not a competing design.

## Result and fixed requirements

Provide one channel facility for ordinary threaded programs, the process pool
service, and `ParallelMap.foldl`. Keep mutable work private until an explicit
handoff. Share canonical immutable storage through at least one process-wide
pool containing both Strings and cons cells.

Preserve `PoolTable` and its existing Robin Hood hashing: layout, probing,
displacement, load policy, and growth. Do not introduce bucket chains or
concurrent table readers. One dedicated native thread owns every operation on
the global table, including lookups, insertion, growth, and table statistics.
Clients read returned immutable objects directly; reading String bytes or List
fields is not a table lookup.

The public API below is proposed new API, not currently executable source.
Names and contracts are settled here for implementation review. Existing
documented APIs remain unless this plan explicitly changes their behavior.

## Architecture and ownership

| Component | Owns | Does not do |
| --- | --- | --- |
| Channel | Queued fixed-size records and synchronization | Infer pointee ownership, intern values, or schedule threads |
| Message | A result value and its detached mutable Scope | Make arbitrary borrowed objects owned |
| Thread | Execution, Error/Match state, and private working storage | Expose live mutable work through a result |
| Pool service | Global canonical storage and the Robin Hood table | Run application callbacks or own mutable objects referenced by Lists |
| Context | A bounded work lifetime and explicit export | Treat global List storage as proof its contents are global |

Ownership is an API obligation, consistent with existing C-style handles.
This work does not add a compiler move checker or a general graph validator.
Synchronization publishes initialized records and all preceding payload writes.
The sender stops accessing transferred mutable storage after acceptance.

## Channel contract

Use a bounded FIFO queue of fixed-size native records, supporting multiple
senders and receivers. A positive capacity is required. Rendezvous channels,
select, timeouts, cancellation, and unbounded queues are outside this change.
Neither client requires them. Their absence does not restrict a later design.

Proposed surface:

```c
typedef struct Channel *Channel;
typedef enum ChannelStatus {
  CHANNEL_OK, CHANNEL_EMPTY, CHANNEL_FULL, CHANNEL_CLOSED
} ChannelStatus;
typedef void (*ChannelDrop)(void *record);

Channel Channel.new(size_t record_size, int capacity, ChannelDrop drop);
ChannelStatus Channel.send(Channel channel, const void *record);
ChannelStatus Channel.try_send(Channel channel, const void *record);
ChannelStatus Channel.receive(Channel channel, void *out);
ChannelStatus Channel.try_receive(Channel channel, void *out);
void Channel.close(Channel channel);
void Channel.free(Channel channel);
```

- Records have native allocation alignment, as with `Thread.start_raw`.
  Over-aligned records are unsupported. Constructor checks size arithmetic.
- A successful send copies exactly one record. Acceptance under the mutex is
  the ordering point. FIFO follows acceptance order, not caller start time.
- Blocking send waits for space or closure. Blocking receive waits for a
  record or closed-and-empty. Only the try forms return FULL or EMPTY.
- Failed sends retain caller ownership. Failed receives leave output untouched.
  Closure is a status, not a sentinel record; all record bit patterns are data.
- Close is idempotent, rejects new sends, wakes waiters, and leaves accepted
  records available to receive. A racing send either succeeds before closure
  or returns CLOSED without transferring ownership.
- Free requires exclusive control and no current users or waiters. It closes
  the queue and drops unread records exactly once. Close alone does not free.
- `drop` is optional. When provided, it releases resources owned by an accepted
  unread record. It runs outside the queue mutex, must not raise, and must not
  use the destroyed channel. Received records are the receiver's obligation.
- Ordinary byte-copy send cannot erase caller aliases. Each record protocol
  defines its borrows and transfers; Message supplies a consuming adapter.
- No fairness promise beyond FIFO records. Each successful receive delivers a
  record to exactly one receiver; channels do not broadcast records.

Implement a preallocated native ring, native mutex, and two condition variables.
There is no allocation, interning, callback, or Error construction under the
queue mutex. The internal status-returning transport works before Pool/Error
initialization. Public construction may raise after releasing native resources.
Unrecoverable native synchronization failures use a nonallocating fatal path;
they must not report a failed send after an accepted ownership transfer.

Use the same queue implementation for public records, pool request/reply
records, and worker job/completion records. There is no second pool-specific
queue implementation. Private typed wrappers may enforce record size; do not
introduce a type-generation framework just for these callers.

## Message ownership transfer

```c
typedef struct Message *Message;
Message Message.capture(Func build);
Var Message.value(Message message);
Var Message.take(Message &message);
void Message.free(Message message);
ChannelStatus Message.send(Channel channel, Message &message);
```

`capture` calls a zero-argument builder in a bounded Context with a detached
Scope and the ordinary global pool. The builder returns the root Var. On
success, the Context releases its Error/Match execution state but seals the
Scope and root into the Message. It performs no intermediate graph export.
On failure, it destroys the unfinished work and propagates the original Error.
Application builders balance resource cleanup and Scope brackets normally.
Capture or re-home the failure data before destroying the builder's Error
state; propagation must not retain pointers into that state. A Message root
may be any Var, including void; ParallelMap keeps its separate void-result rule.

The Message owns all allocations made in that work Scope. Detached scopes or
native allocations created separately remain explicit application obligations.
References outside the owned Scope must be process-lived values or documented
borrows that outlive the receiver's use. Global cons cells may reference owned
payloads inside the envelope. Mutable aliases retained by the producer must
not be used after transfer. No runtime reachability proof is added.

`Message.send` requires a channel of Message-handle records. It enqueues the
handle, clears the caller's handle on OK, and leaves it unchanged on CLOSED or
another failure. The queued record then owns the Message. A receiver obtains
that sole ownership. Such channels use the Message drop adapter for unread
records. Channel handles themselves are borrowed, not moved with each send.

`value` borrows the root while the Message lives. `free` destroys the sealed
Scope and envelope. A cleanup adapter makes local ownership usable with
`$auto`; cleanup follows the existing no-raising Scope-finalizer contract.

`take` consumes and clears the Message, exporting the root into the receiving
Scope through the existing graph-aware Context exporter. It always destroys
the envelope, including if export raises. Its failure is consuming and cannot
be retried, matching consuming Thread join. Existing partial-export semantics
remain; this operation does not promise rollback of nested transfers.

This deliberately distinguishes two operations:

- Channel delivery moves the sealed ownership handle without graph traversal.
- Taking a value out of its envelope exports the reachable result, then frees
  temporary allocations left in the envelope.

Do not introduce wholesale Scope adoption in this change. Containers cache
their owning Scope, and Context export uses ownership to decide what moves.
Keeping those relationships correct requires more than splicing allocations.
The selected design removes the first worker export while reusing the current
owner for the final import. Map rebuilding on that final import is initially
retained; eliminating it is a measured follow-up, not a prerequisite.

## Global pool service

### Lifetime and request protocol

Create the global pool during runtime initialization. It survives through all
application threads, shutdown hooks, static finalizers, and Error/Logger cleanup.
Release its immutable storage only after every borrower has finished.
Global canonical values are process-lived; no eviction or garbage collection
is introduced. Retained full-file Strings are an explicit memory tradeoff.

One client has at most one synchronous request outstanding. Each registered
client has a capacity-one reply channel. The shared request channel is bounded;
begin with capacity 64, an implementation constant rather than a public tuning
API. Full capacity blocks admission and does not discard requests.

Use fixed native records for operations such as String lookup/intern, cons
lookup/intern, promotion/ownership operations, and statistics snapshots.
A request names a native request record and its reply channel. Input bytes and
the record remain alive and unchanged until the reply. A cons request borrows
its head and tail through completion. Replies carry a value plus a native
status and compact failure fields, without constructing diagnostic Lists.

The owner processes one request completely, searches before allocating, and
publishes one canonical identity. Simultaneous equal requests receive the same
pointer. Only the owner accesses table metadata. Length, cached hash, String
bytes, and published cons fields remain directly readable by clients.

Proposed advanced-API compatibility change: the global pool accepts canonical
String and List keys, with Atoms represented through their String storage.
Its hash/equality operations are intrinsic and cannot call application code.
Generic `Pool.lookup`/`intern`/`insert` signatures currently accept Var, and
custom hash/equality can run there. Preserve generic custom-key operations in
explicit private pools; reject unsupported global key kinds on the requesting
thread before submission. Do not silently run those callbacks on the service
thread or invent a second global generic table. Document this narrowing in the
advanced Pool reference and migration notes. It is a proposed public contract
change for review, not an existing restriction inferred from current callers.
Private custom-key searches do not submit unsupported probes to the global
ancestor; that ancestor cannot contain a custom-key match. Promotion of a
custom key into the global pool is likewise outside the narrowed contract.

Route advanced global candidate insertion, promotion, and ownership changes
through owner requests too. Preserve their documented pointer/lifetime rules;
transfer candidate storage only at the operation's defined acceptance point.
Do not leave direct global writes in promotion or buffer-finalization helpers.

Replies cannot block the owner indefinitely: one outstanding request per client
and capacity one reserve the response slot. Clients cannot cancel a submitted
request or destroy its buffers/reply channel before receiving the response.
Request failure replies are delivered before the requester raises in its own
Error state. Unexpected loss of the runtime owner terminates through the native
fatal path; this design does not add service restart or recovery supervision.

Keep the single-value APIs. Add a String-span batch request for clients that
already possess several tokens; output slots follow input order. A batch is
bounded to 256 spans per request and larger inputs submit successive batches.
Partial insertion before failure is allowed, but no partial result is returned
as success. Existing `String.words` is not silently changed to eager iteration.
Do not add batching for dependent cons construction without a concrete caller.

### Bootstrap, recursion, and shutdown

Start the owner with a minimal native thread entry below ordinary `Thread.start`.
Ordinary Thread startup already needs pools and Error machinery. Register this
runtime-owned thread separately from user threads that must be joined.

Initialization creates Scope/native channel storage and the initial global
table under one bootstrap owner, then hands exclusive ownership to the service
before exposing normal pool calls. No public interning runs during the handoff.
The owner's internal operations execute directly; they never send to themselves.
Enable shared allocator/depot synchronization before starting this native owner,
even when no application Thread has started. The service is a real concurrent
user of shared backing storage. A client must release allocator/depot locks
before waiting for an owner request that could need those locks.

Owner allocation/table failure handling must not call public global interning,
Logger formatting, or application callbacks. Factor the minimum native-status
failure path needed from current pool/table operations while retaining the
Robin Hood algorithm. Preserve private diagnostic storage. An unreportable
allocation failure uses the existing nonallocating fatal boundary.

Shutdown keeps the service alive until all code that can intern has completed.
Then prevent new clients, close and drain requests, join the owner, and finally
destroy the global table and storage. Scope's low-level shutdown orders this
after pool-using hooks and finalizers, before allocator shutdown. Do not rely
on registration order alone. No use of public global interning is allowed
after the service stops. Initialization and partial-start failure unwind native
resources without depending on the service being available.

### Canonical values, private pools, and writable buffers

Ordinary Thread callbacks and Message builders use the global pool rather than
implicitly creating per-job canonical pools. Their mutable Scope, Error, and
Match state remain private. This changes automatic Thread temporary retention:
ordinary canonical temporaries now survive until process teardown.

Preserve explicit `Pool.open`/`Context.open_isolated` lifetimes and private Error
record pools. They remain opt-in bounded canonical storage. Private pools have
one execution owner; their chain lookup reaches the global table only through
the service. They cannot be passed to another thread while active. This does
not make every private pool globally readable.

A cons request preserves the supplied head bits and tail pointer, including
explicit cross-pool borrows. Do not silently globalize private canonical
children: that would change `List.cons_in`'s identity contract. The client keeps
all borrowed children alive through every use of the resulting cell, not just
through the reply. Preserve arbitrary non-void Var heads, including mutable
handles and boxed scalars. A global cell is not a promise that its complete
graph is process-lived or race-free.

Explicit Context export, rather than ordinary cons construction, globalizes
private canonical children when a result must survive their pool. Finish that
traversal before destroying the private source pool. Owner-side constructors
use direct internal operations and never recursively submit a service request.

`String.malloc` and other unfinished String buffers remain client-owned mutable
storage. Preserve explicit bracket reclamation and existing finalize/free
contracts. Only finalized bytes enter the global service. Finalization consumes
or retains its input exactly as the current API specifies; it must not publish
a writable buffer as a canonical String.

Context export must traverse List heads even when cons cells are global.
The current source-pool ownership early exit would hide worker-owned Maps,
Arrays, and boxed scalars. Move Scope-managed contents through existing
exporters; rebuild canonical cells only where an exported head or tail changes.
Preserve sharing, supported cycles, and identity rules. A plain global
String needs no copying. Global cons storage alone cannot justify a traversal
early exit. Keep explicit private-to-destination canonical export supported.

## Thread and parallel_map integration

Keep public Thread callback signatures, borrowed-input rules, consuming join,
Error policy, and join-fail reporting. One-shot Thread completion stores a
Message or captured failure envelope. Join takes the result once. Remove the
intermediate result pool and callback-to-result canonical export. Worker Error
snapshots must survive Error-state teardown in their owned envelope.

`Iter.parallel_map(function, workers).foldl(seed, accumulate)` keeps its public
surface and lazy startup. Its implementation uses:

- One capacity-one job inbox per worker.
- One completion channel of capacity `workers`, shared by all workers.
- A completion record containing worker identity and an owned success/failure
  Message. A job borrows the source value under the current read-only contract.

The caller assigns one initial job per worker. A worker captures a result,
sends its completion, and waits for another job. The caller receives a ready
completion, takes its value, applies the accumulator, and only then gives that
worker another input. Only the caller traverses the source and accumulates.
There is no producer thread, eager result Array, or enqueue-all dispatch loop.

The scheduling sketch below uses the same Channel operations as the pool
service. Types and Message construction are schematic, not runnable example
source. `take_completion` owns the received envelope before it can raise.

```text
inboxes[i] = Channel.new(sizeof(Job), 1, NULL)
completed  = Channel.new(sizeof(Completion), workers, drop_completion)

caller: assign at most one initial Job to each inbox
worker: while inbox.receive(job) == OK:
          result = capture callback result or failure in an owned Message
          completed.send(Completion(worker_id, result))
          relinquish the accepted Message
caller: while jobs remain outstanding:
          completed.receive(completion)
          item = take_completion(completion)
          accumulator = accumulate(accumulator, item)
          if source has another input: inboxes[completion.worker_id].send(job)
```

Completion order is FIFO successful publication, not source order or callback
return timestamps. Each worker has at most one accepted job or unread result.
Preserve empty input, void seed/result, worker bound, source lifetime, and
temporary-Iter rules documented in the tutorial continuation.

On source, worker, import, or accumulator failure:

1. Close all job inboxes. Busy workers finish accepted callbacks; none are
   cancelled. No new inputs are assigned.
2. Leave completions open and join every worker. At most one completion per
   worker can remain, so capacity `workers` permits every final send even when
   the caller has stopped receiving. Previously consumed slots only help.
3. Drain/drop unread completion envelopes, then free channels and handles.
4. Preserve the primary Error; report cleanup failure under existing rules.

Remove `ParallelRun.ready`, assignment flags, and its private completion
condition protocol. Ordinary Thread wait-any notification may remain for that
distinct API; do not keep a second queue for ParallelMap. Do not require select
merely to replace this scheduling loop.

## Implementation and verification

Implement in dependency order as one connected change. Local checkpoints and
bootstrap transitions follow existing repository rules, without an extra gate
per component.

1. Implement the raw Channel core and the public fixed-record contract.
2. Implement Message capture, consuming send, destruction, and final import.
3. Implement the process service, lifecycle, and public interning facade over
   the unchanged Robin Hood table. Keep private pools explicit.
4. Correct global-List graph export, retain private buffer semantics, and move
   Thread completion to one sealed envelope.
5. Replace ParallelMap's private queue/assignment machinery with channels.
6. Update the contexts/threads and collection lifetime book sections and add a
   small channel ownership example. Preserve V7's source and visible results.
7. Review and fix the complete authored diff, then run applicable publication
   validation and performance work under the existing repository instructions.

Focused evidence must cover:

- MPMC delivery without loss/duplication; FIFO acceptance; bounded blocking;
  close races, draining, unchanged failed outputs, and exact-once drops.
- Message acceptance/rejection ownership, producer exit before receive, queued
  cleanup, consuming import failure, and custom finalizer thread/lifetime rules.
- Equal concurrent String/cons requests returning one pointer, repeated table
  growth, reply backpressure, bootstrap failure, and interning during teardown.
- Global Lists containing worker-owned Maps/Arrays and wide boxes, nested and
  repeated values, supported mutable cycles, and explicit private canonical
  children surviving transfer. Preserve exact cons identity semantics.
- Existing Thread and ParallelMap result/failure contracts, reused workers,
  blocked-job progress, and source/worker/accumulator failure cleanup. Exercise
  more jobs than channel capacity and final publication without a draining
  caller to reproduce the relevant deadlock risks deterministically.
- V6/V7 output parity on nested files and an empty directory.

Reuse existing suites and publication targets. Add no recurring gate or new
process stage. Keep full failure logs in `debug/`; temporary probes belong in
`/tmp` or `unittest/build/`.

Performance evaluation compares current code and the proposed implementation
on the same machine/toolchain/corpus, with one and four application workers
(report the additional owner thread). Include repeated and disjoint vocabulary,
short and long Strings, and dependent cons construction. Record elapsed time,
CPU time, peak retained memory, request counts/batch sizes, and existing pool
storage counters. Measure end-to-end V7 as well as isolated interning. Global
retention and service serialization are explicit costs; neither throughput
improvement nor unchanged memory use is assumed. Measurements inform tuning or
a revised implementation, not rejection of all channel-based ownership designs.
Include compiler translation and meta-helper startup in the existing applicable
performance checkpoint: these processes intern heavily even with one application
thread. Do not hide the new owner-thread cost behind a word-count-only result.

This planning request ends with the reviewed plan. It does not authorize
runtime edits, API migration, a build, publication, or a new release.

## Evidence and design review

Current source anchors:

- `lib/map-generics.x`: Robin Hood displacement and replacing backing arrays.
- `lib/pool/interning.x`, `lib/pool/threads.x`: current table locking, root
  sharing, and private ancestor-chain lookup.
- `lib/string/storage.x`, `lib/list/list.x`, `lib/list/cells.x`: canonical
  construction, writable buffers, exact cons identity, and borrowed payloads.
- `lib/context.x`: graph export and the List ownership early exit to replace.
- `lib/scope/regions.x`, `lib/scope/allocation.x`: detached Scope lifetime,
  allocator ownership, and pointer-preserving movement.
- `lib/thread.x`: two result ownership boundaries and existing fold scheduling.
- `lib/error/records.x`, `lib/common.x`, `lib/scope/runtime.x`: private Error
  storage, initialization dependencies, and shutdown hooks/static finalizers.
- `plans/c2x2c-continuation.md`: saved V7 contract and open thread/channel design.

The design reuses the current hasher, allocators, graph exporters, and callback
contracts. It deletes duplicate ParallelMap communication and one result export
boundary. Channel ownership remains explicit instead of becoming an inferred
deep-copy or graph-validation facility. The native transport breaks the pool
bootstrap cycle. Capacity and dispatch order establish a concrete cleanup
progress argument. The main risks are service serialization, global temporary
retention, and correct export of scoped payloads behind global cons cells.
These are implementation and measurement obligations, not validated outcomes.
