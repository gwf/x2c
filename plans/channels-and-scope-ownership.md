# Channels, Thread batches, and explicit scope ownership

> Status: active
> Unified design agreed on 2026-10-22 after Channel, threading, and error-design
> chat review. Gary accepted Thread.run and the explicit worker completion count.
> This document is the single contract for their connected work. Optional
> Channel constructor/tag defaults remain proposals where marked below.
> Implementation authorized by Gary on 2026-10-22. The coordinating chat owns
> combined integration, validation, and direct delivery; Channel and Thread
> workers provide private handoffs and do not publish independently.

## Result and scope

Provide Channel communication, explicit storage-scope ownership, and synchronous
Thread.run batches. Channels carry non-void Vars without changing ownership.
Developers arrange lifetimes and coordinate mutable access. Thread.run owns its
started Threads and failure cleanup; Channels own queueing and normal close/drain.

The selected example has a filename producer, four persistent counting workers,
and a consumer. The producer closes files. A completion callback closes results
after all four workers succeed. On failure the batch stops all remaining jobs
before joining any of them, then propagates the triggering error.

Batch jobs use the shared process canonical pool by default and separate mutable
work scopes. This makes filenames and word keys safe without individual String
handoff. Deliberately shorter-lived pools and borrowed buffers remain explicit
lifetime responsibilities.

This supersedes automatic sender identification/registration, startup holds,
parent error injection, Thread links, and channel-carried failure proposals.
There is no close(error), failed-channel state, task_scope, Producer wrapper,
automatic payload adoption, recursive transport export, or inferred dependency
on all users of a Channel. Ordinary Thread.start/join and ParallelMap remain
compatible. General callable.go is deferred, not needed by this selected batch.

The [tutorial continuation](c2x2c-continuation.md) records existing behavior.
The contracts below describe intended additions, not implemented capabilities.

## Agreed ownership semantics

- Each thread, including main, has a root Scope. Normal thread cleanup
  destroys storage still owned beneath that root. Main's lifetime must cover
  its workers; process shutdown must not destroy their borrowed storage first.
- Each Map and Array has a storage scope containing its stable handle and
  required backing allocations. Growth keeps storage in that ownership unit.
- Scope lifetime ownership is a hierarchy with one owner and no cycles.
  Object references form a separate graph that may contain aliases and cycles.
- Transferring an object's storage scope detaches it from its previous owner
  and attaches it beneath the destination scope. It preserves addresses and
  does not clone, rehash, or traverse the object's keys, values, or elements.
- Destroying a scope destroys its allocations and adopted child scopes.
  Destruction does not follow object references. Each allocation is reclaimed
  once, with its existing native-resource finalizer when applicable.
- Nested mutable values retain independent lifetimes unless explicitly
  adopted. Inserting a Map into an Array does not adopt the Map automatically.
- Developers may build a graph whose node scopes are siblings beneath one
  graph scope. Destroying that common scope releases the graph despite
  reference cycles. A reference to a node does not grant destruction authority.
- Developers own lifetime and access correctness: no simultaneous readers and
  writer, no competing writers, and no access after destruction. Transfer
  changes lifetime ownership, not aliases or permissions to access data.
- Immutable backing storage must also outlive all borrowers. Private-pool
  Strings or cons cells do not become safe merely because their containing
  Map moved. Immutable cons cells may reference mutable objects.
- Sending and receiving copy Var representations only. Neither operation
  changes the ownership of referenced storage, including boxed wide scalars.
  Neither operation grants exclusive access, revokes sender access, or requires
  a transfer. Storage ownership and the application's access agreement remain
  independent of channel communication.

Reparenting must do constant work with respect to object size and adopted
descendant count. Reclamation remains proportional to storage reclaimed.
No universal constant-time claim applies to owner lookup, allocation,
locking, or diagnostics. Ownership cycles and destruction during active use
are invalid caller operations; do not add whole-graph lifetime validators.

## Proposed ownership API

The conversation used field notation for clarity:

```c
map.scope.transfer(array.scope);        // become the Array's child
node.scope.transfer(peer.scope.owner); // become the peer's sibling
```

Use read-only methods in the first implementation rather than introduce
property syntax or publicly writable ownership links:

```c
map.scope().transfer(array.scope());
node.scope().transfer(peer.scope().parent());
```

`object.scope()` returns its complete storage scope. `scope.parent()` returns
the enclosing lifetime owner, distinct from the active allocation destination.
`scope.transfer(destination)` moves the complete ownership subtree. Transfer
to the existing owner is a no-op. Thread roots are not transferable children.
Each private object scope is initially attached to the active allocation scope.

An object's explicit free destroys its storage scope and adopted descendants.
It does not destroy its enclosing owner or siblings. Destroying a common graph
scope is an explicit operation on that scope. Existing aliases, including
separately scheduled cleanup calls for adopted children, become invalid after
parent destruction; the developer must have one destruction responsibility.

Preserve `Scope.owner(allocation)` as the allocation-owner query; use
`scope.parent()` for the lifetime parent to avoid a conflicting signature.

Keep Scope push/pop and retain/release behavior distinct from ownership links.
Changing the active allocation destination neither transfers nor frees storage.

## Observed implementation and required changes

Source inspected at local HEAD `e2a78078edece1348abbbb7363c89560ae064706`.
This is not a claim about the current remote tip; implementation must fetch
and inspect its actual starting tree.

| Owner | Current behavior | Required work |
| --- | --- | --- |
| `lib/scope/scope.x`, `regions.x` | Per-thread roots, active slots, pushed slots, and retained-region chains. | Add lifetime owner/child links separate from execution stacks; reclaim adopted subtrees. |
| `lib/scope/allocation.x` | Relinks individual allocations; `Scope.owner` scans backward to a tagged list head. | Preserve allocation contracts; add subtree reparenting and protect shared ownership metadata. |
| `lib/map-generics.x` | Map and two backing Blocks start in the current scope. Map remembers that scope; growth moves staged replacement storage there. | Give the Map its own attached storage scope; retain growth exception safety; free through that scope. |
| `lib/array-generics.x`, `array.x` | Array is a Block view. Constructors, copies, and slices use `Block.new`; cleanup delegates to Block free. | Give Array construction and destruction the same storage-scope boundary as Map, including literals and derived Arrays. |
| `lib/block.x` | Type-agnostic handle and backing allocation; reserve preserves backing allocation ownership; free releases both allocations explicitly. | Keep Block type agnostic and preserve raw Block/Bytes contracts. Do not make Block inspect elements or adopt payloads. |
| `lib/context.x`, `map.x`, `typed-array.x` | Explicit export recursively exports values; Map export can rebuild keys and storage. | Adapt storage movement to the new scopes while preserving existing documented explicit-export semantics. Channel transport must never call this exporter. |
| `lib/thread.x`, `thread-state.x` | Workers have thread-local roots and isolated callback Contexts; joins export sealed results. | Preserve existing Thread and ParallelMap contracts; verify adopted results survive worker-root cleanup. |

Array's Block representation does not justify an Array-specific policy in raw
Block operations. Implement an Array lifecycle entry point instead of leaving
its destructor delegated to raw Block free. If generic storage metadata is
needed to retain the representation, keep it type agnostic. Review typed
collection constructors/cleanup for compatibility with the changed lifecycle;
do not introduce typed Channel families or redesign typed collection macros.
Var remains a value carrier, not an automatic owner of the referenced graph.

## Core channel surface

The agreed shape is one Channel type, symbol-based optional message constraint,
Var send/receive, optional capacity, and void reserved for exhausted reception.
No channel type or dedicated queue implementation is generated per payload type.

```c
Channel.new()                  // unrestricted, unbuffered
Channel.new(16)                // unrestricted, capacity 16
Channel.new(<map>)             // Map values, unbuffered
Channel.new(<map>, 16)         // Map values, capacity 16
Channel.new(<map>, <unbounded>) // uncapped buffering
```

Recommended first-version defaults not separately settled in conversation:

- Normalize constructor forms through one ordinary constructor implementation
  and a small argument macro if needed. Do not add general function overloading.
- Use `<var>` as the unrestricted type symbol, including
  `Channel.new(<var>, <unbounded>)`. Capacity zero means rendezvous; positive
  integers mean a hard queue bound; `<unbounded>` means no configured bound.
  Other capacities raise `<bad-arg>`.
- Validate constrained messages before acceptance using existing Var type/tag
  facts, without conversion. Canonical tags include `<map>` and `<i32>`;
  earlier illustrative `<int>` spelling must not silently mean a nonexistent
  exact Var tag. Document the supported symbol vocabulary before implementing
  numeric aliases or broader type categories.
- `send(value)` blocks until acceptance and returns no value. Sending void or
  a mismatched type raises before acceptance. A closed channel raises
  `<bad-state>` for send, including senders awakened by closure.
- `receive()` blocks until a message or closed-and-empty state. It returns
  the accepted value, or void after normal close and draining. Null remains
  valid data on an unrestricted channel.
- Any coordinated holder may close; designate a closer in application code.
  Close is idempotent, rejects new sends, and wakes blocked operations.
  Accepted messages drain. Multiple producers do not trigger implicit closure;
  a coordinator closes after they finish. Producer-counted endpoints are deferred.

Acceptance is a synchronized queue insertion for buffered channels, or a
synchronized sender/receiver match for rendezvous. Close and acceptance use
the same synchronization boundary: a send is either accepted or rejected,
never both. Successful send does not mean processing has finished. Preserve
FIFO queue order; do not promise scheduling fairness among competing threads.

Channels have their own attached storage scope, available through `scope()`.
Queue storage and native synchronization are owned there. The channel does
not reclaim arbitrary referenced payloads on close or drain. Explicitly adopted
payload scopes remain children until moved or destroyed. Channel destruction
requires no active users or waiters. On normal completion, close and finish users
before destruction. After failed-batch teardown has joined every user, Channel
cleanup may close the still-open channel and destroy it. Cleanup does not join
users or infer which Threads use the channel.

Use raw Var queue storage and native synchronization independent of canonical
interning. A ring buffer or a type-agnostic Block is sufficient; do not build
transport by reusing ParallelMap's private completion Array. An unbounded
channel can still fail allocation. Keep queue locks off ambient Error handling,
user callbacks, and payload destruction; publish failures after unlocking.

Nonblocking operations and select remain deferred. Failure coordination belongs
to Thread.run, as specified below. Channel operations participate in cooperative
Thread stopping without storing task failures or closing unrelated Channels.
Normal close/drain remains an explicit application protocol.

## Sharing without transfer

The default channel operation is communication with unchanged ownership:

```c
// Parent owns this Map and keeps it alive until every worker finishes.
Map configuration = load_configuration();
inputs.send(configuration);
inputs.send(configuration);
// Workers may concurrently read the same Map. Parent does not write while
// readers are active. No participant needs to transfer its scope.
```

The parent and workers agree on access; the channel does not impose exclusive
handoff. The same applies to nested references and to worker-owned messages.
A worker may retain ownership of a sent result if it stays alive until its
borrowers finish, or if another explicit lifetime arrangement protects storage.
Successful send alone is not evidence that borrowers have finished.

## Worker result lifetime with explicit transfer

Illustrative code, with proposed APIs:

```c
// Caller creates results under an owner that outlives all workers.
Channel results = Channel.new(<map>, 4);

// Worker arranges any nested mutable ownership explicitly first.
Map result = count_words(path);
result.scope().transfer(results.scope());
results.send(result);
// For this example, worker and consumer agree that the consumer alone uses
// the result after send. Worker may now exit without destroying the result.
```

This is an optional lifetime arrangement, not an additional send contract.
Transfer is needed here because the worker wants to exit before consumption,
not because the channel received a Map or because the consumer reads it.

The caller can consume while results remains alive. To retain a result beyond
the channel lifetime, transfer its scope beneath the accumulator or another
explicit owner. A separate failed send does not undo a completed transfer.
The unsent result remains channel-owned until explicitly destroyed or moved,
or until channel-scope destruction. Dequeued results also remain there unless
explicitly moved or destroyed; draining does not bound retained payload memory.
For streaming accumulation, merge each result and then destroy its scope.

Transferring into a shared channel scope must be safe when several workers
do so concurrently. Scope allocation lists, child links, free/realloc, and
teardown must follow one consistent synchronization policy. Developers remain
responsible for excluding destruction during use and for synchronizing payload
access; internal ownership metadata must not race between valid operations.

## Agreed Thread.run contract

Proposed spelling: Thread.run(Array jobs, optional Func completed). This is a
synchronous operation on zero-argument callables, not already-started handles.
Each job returns a Var, including void. An empty batch returns without calling
completed. The operation itself returns no value; successful job results go to
the optional completion callback or are ignored. Ordinary argument macros may
normalize the optional callback; no general overloading is required.

- The caller keeps jobs, their callable storage, code, captures, and borrowed
  targets alive throughout the call. Thread.run does not mutate jobs. Shared
  mutable captures remain subject to ordinary access and lifetime obligations.
- Reserve handle storage and install cleanup before starting anything. Record
  every successfully started handle without allocation or an ownership gap.
  Partial startup failure leaves unstarted jobs unexecuted.
- Observe completion through the existing wait_any/finish_any mechanisms,
  extended for stop-aware coordination. Completion observation does not wait
  for an earlier unfinished job merely because it appears first in jobs.
  Simultaneously ready jobs need no chronological ordering guarantee.
- Join/export a successful job before invoking completed(result), once on the
  calling Thread. A void result is still a successful completion. The callback
  performs short coordination and must not wait on participant progress.
- Completion results have ordinary joined/exported ownership in the caller's
  active Scope/pool, not borrowed storage in a freed Thread. No per-callback
  reclamation is silently added. Callers release or move retained mutable
  results explicitly. Unobserved sealed results are reclaimed during cleanup.
- On startup, job, export, completion-callback, or coordinator-stop failure,
  preserve the triggering error. Request stop on ALL remaining participants
  before joining ANY remaining participant. Join/release every started handle,
  then propagate that error. Invoke no completion callbacks during this cleanup.
  First observed failure is sufficient; chronological-first error is not promised.
- Cleanup joins mask pending cancellation until participant lifetimes end.
  Secondary stop/join errors must not replace the preserved triggering error.
  Existing ordinary join retry behavior remains unchanged. If a native join
  failure prevents establishing completion during batch teardown, do not return
  and release borrowed storage; fail fatally unless safe completion is established.
- Never return with live participants. This is a storage-safety requirement,
  not a termination guarantee: cooperation cannot stop arbitrary computation,
  arbitrary native I/O, or code that catches and ignores stopping indefinitely.

Thread.run's explicit job list defines its authority. It does not inject child
errors into unrelated joins, change ordinary Thread.join semantics, or infer
membership from Scope ownership, captures, Channels, or service users.

## Cooperative Thread stopping and Channel waits

Thread.stop is a persistent, idempotent cooperative request. Its spelling and
runtime implementation are additions, not existing behavior. Stopping a Thread
does not close its Channels, destroy messages, or stop unrelated users.

A Channel operation registers its wait with the calling Thread. Stop publishes
pending state and wakes that registered wait. Registration, pending checks,
unregistration, and waiter lifetime must prevent lost wakeups and use-after-free.
A stop before registration remains observable; a stop while blocked wakes the
operation. No caller-maintained waiter collection is required.

Check pending stop before acceptance/delivery. Buffered insertion and dequeue
have synchronized commit points; rendezvous commits its matched send/receive
together. If stop precedes commitment, the operation leaves without accepting
or delivering and raises after unlocking. If commitment precedes stop, that
operation succeeds; later stop does not retract acceptance or report the same
committed operation as failed. A subsequent operation observes pending stop.
Normal close uses the same synchronization discipline as acceptance.

Stop notification must not allocate, intern, run user callbacks, or raise while
Thread/Channel locks are held. Transport storage and wakeup synchronization do
not depend on canonical interning. Raise cancellation only after unregistering
and releasing queue locks. A stop-induced receive is never successful EOF.
The concrete lock/notification protocol is implementation work that must meet
these outcomes, not a selected new public abstraction.

A pending stop at an ordinary runtime wait produces an unwinding cancellation
outcome. Ambient resumable Error policies must not turn it into a successful
return or resume the wait. User code may explicitly catch cancellation, so
termination remains cooperative. The exact cause spelling is an implementation
detail; this does not change unrelated user-defined Error policies.

Coordinator completion waits are also stop-aware. A stopped job coordinating a
nested Thread.run wakes, stops its nested participants, joins them with cleanup
interruption masked, then propagates failure. A Thread interrupted during batch
failure is not reported through completed, even if it catches stop and returns.

## Shared process canonical pool

Every batch job begins with the shared PROCESS canonical pool active. It does
not inherit a shorter-lived caller pool and does not automatically open private
callback or result canonical pools for job execution. Separate mutable work
scopes and Error/Match Context state remain bounded normally. Context.open_named
is an existing example of bounded mutable state without a private canonical pool;
reuse that separation rather than removing Context cleanup.

All jobs in the example intern filenames, words, and intermediate Strings in
that process pool. Their canonical storage outlives jobs and the returned Map.
Pool lookup/insertion already has synchronized paths enabled before worker
startup. The new batch path must preserve that initialization and locking.

The process pool retains these values until process shutdown. Bounded Channel
capacity does not bound canonical-pool memory. This is an accepted lifetime and
retention tradeoff, not a performance claim. Canonical Lists may still reference
mutable objects with independently managed lifetimes.

Deliberately opening a private pool retains its existing documented semantics.
Pool storage and borrowed bytes must survive their last real borrower. Scope
transfer never makes private-pool keys safe. Stopping a client is not evidence
that a service has stopped borrowing its request storage.

Keep error snapshots in independently owned storage until observation and
cleanup complete, including their records and wide boxes. Completion results
retain ordinary joined/exported ownership. Explicit private-pool results still
need correct export before their pool closes. Do not silently change ordinary
Thread.start/start_raw/join or ParallelMap private-pool/result contracts.

## Selected word-count example

Illustrative intended x2c; this code has not been compiled. Channel, scope
ownership, and Thread.run are additions. Reference capture in the completion
callback is existing syntax and is required for updating remaining_workers.

```c
static Map word_count(Path filename) {
  String text = filename.open("r").string_close()
    .filter(%!(unsigned char c) => !ispunct(c)).lower();
  Map counts = {};
  foreach (String word in text.words())
    counts[word] += 1;
  return counts;
}

static Map directory_count(Path root) {
  Map counts = {};
  Channel files = $auto(Channel.new(4));
  Channel results = $auto(Channel.new(4));
  Array jobs = $auto([]);
  int remaining_workers = 4;

  jobs.push(%!(void) => {
    foreach (Path filename in root.walk().filter(Path.is_file))
      files.send(filename);
    files.close();
    return <producer>;
  });

  for (int i = 0; i < remaining_workers; ++i)
    jobs.push(%!(void) => {
      foreach (Path filename in files) {
        Map part = word_count(filename);
        part.scope().transfer(results.scope());
        results.send(part);
      }
      return <worker>;
    });

  jobs.push(%!(void) => {
    foreach (Map part in results) {
      counts.merge_with(part, %!(int a, int b) => a + b);
      part.free();
    }
    return <consumer>;
  });

  Thread.run(jobs, %!(Var completed) using &remaining_workers => {
    if (completed == <worker> && --remaining_workers == 0)
      results.close();
  });
  return counts;
}
```

Producer closes files. Workers drain it; the caller's completion callback closes
results after all four workers succeed. Consumer drains results. No completion
callback runs during failure cleanup. Only consumer writes counts; the caller
uses counts after Thread.run succeeds. No transfer of counts is needed.

Each worker transfers a part's storage scope beneath results before sending.
For this example the worker stops accessing part after successful send. The
consumer merges and calls part.free directly. Process-pool keys remain valid.
Nested mutable objects would need separate adoption; this example has integer
values. An undelivered Map or failed send after transfer leaves storage beneath
results. Channel destruction reclaims it only after Thread.run finishes all jobs.

## Failure traces and request/response boundary

- A counting worker fails: completion observation reports its error; the batch
  stops producer, other workers, and consumer before joining. A producer blocked
  sending files wakes on its own stop. Workers blocked sending results or
  receiving files wake on their stops. A blocked consumer receive also wakes.
  Running computations reach a stop-aware operation cooperatively. No Channel
  is marked failed or automatically closed; no partial counts is returned.
- Consumer fails while result sends block: its completion exposes failure, then
  stop wakes those senders and any producer blocked on files. Cleanup joins all
  participants before adopted Maps or shared inputs are destroyed.
- An owned service and its clients are jobs in one batch. Clients return a
  client-completed tag; the short completion callback closes requests after the
  last client succeeds. Service drains requests and exits normally. A service
  failure stops all batch clients, waking blocked request sends and per-request
  reply receives, including requests the service never read. Request-specific
  rejection is an ordinary error reply, not necessarily service failure.

Keep request bytes valid until the service acknowledges completion or actual
borrower completion is established. After a client stops, its callback cleanup
must not destroy storage still borrowed by the service. Use an enclosing owner
that survives the whole batch where that is the simplest arrangement. Canonical
pool storage must outlive all canonical-reference borrowers independently of
service Thread completion; a pool-owner service remains an optional architecture.

Independently owned services shared by unrelated computations are outside batch
cancellation authority. They need an explicit dependency-wait or guaranteed
failure-reply protocol; that API is outside this first design. Do not claim this
batch fixes arbitrary borrowed-service reply waits or makes cancellation an
acknowledgment. Channel queueing and response transport must work without interning.

## Implementation sequence

1. Inspect current source and existing Scope, collection, Context, and Thread
   tests. Confirm Array construction paths, explicit cleanup dispatch,
   finalizers, and canonical-pool lifetimes. Reuse their current owners.
2. Implement attached lifetime scopes, owner queries, and subtree transfer.
   Keep active/retained execution state separate. Choose the smallest locking
   policy that handles several workers adopting into one live owner safely.
   No tracing, reference counting, borrowed-graph registry, or lifetime checker.
3. Update Map and Array construction, growth, copy/slice/literal construction,
   and destruction to use storage scopes. Preserve stable handles, shallow
   element semantics, and existing raw Block/Bytes behavior. Update explicit
   Context exporters without routing channel messages through them.
4. Implement core Channel construction, scope access, send, receive, close,
   and native-resource cleanup. Implement rendezvous, bounded, and unbounded
   queues through one synchronized channel state owner.
5. Add cooperative Thread stop and stop-aware Channel/completion waits. Keep
   synchronization commits, stop publication, waiter lifetimes, and unlocking
   before raising in one connected design. Preserve ordinary Thread contracts.
6. Add Thread.run through existing callable adapters, result export, completion
   observation, and deferred cleanup. Reserve registration storage before start;
   implement the shared process-pool job policy and stop-all-before-join teardown.
7. Add the selected word-count example and an owned service/client batch example.
   Use ordinary Iter conventions for Channel foreach; void is excluded from data.
   Document borrowed-request lifetime through actual borrower completion.
8. Update the book with storage ownership, close/drain, batch lifecycle, stopping,
   shared process-pool retention, and compatibility boundaries. Review and fix the
   complete authored diff before publication validation, including regenerated
   artifacts through their owners.

Do not replace ParallelMap or rewrite the eight saved tutorial versions in this
scope. Use their current behavior as compatibility evidence. No new scheduler,
public batch/group object, .go implementation, or pool-owner service is included.
The optional Channel constructor/tag details marked above remain proposals to
settle before their implementation; do not infer additional numeric aliases.

## Focused validation and delivery

Use the existing unit harness and publication targets; add no recurring gate.
Exercise behavior rather than implementation layout:

- Preserve Map/Array identity and contents across transfer and later growth.
  Release the source owner, then use and destroy the destination-owned object.
- Adopt nested containers; destroy through the parent; verify one reclamation
  per allocation. Preserve independently owned nested containers separately.
- Build cyclic references among sibling nodes and release their common owner.
- Send one parent-owned Map to several workers without any transfer. Verify
  unchanged ownership and concurrent read-only use; parent retains storage
  and avoids writes until the workers finish.
- Have several workers transfer disjoint result scopes into one live channel
  owner. Exit workers before consuming retained results. Transfer a received
  result elsewhere and verify it survives channel destruction.
- Verify rendezvous blocks until a match; bounded sends resume after receive;
  unbounded sends queue without waiting for capacity. Use deterministic thread
  coordination rather than sleeps to establish ordering.
- Verify close wakes senders/receivers, drains accepted values once, and returns
  void thereafter. Cover null data, void/type rejection, and close/send races.
- Exercise partial startup, job, result-export, callback, and coordinator-stop
  failures. Prove stop-all occurs before cleanup joins and no completion callback
  runs during failure cleanup. Preserve the triggering error and release handles.
- Exercise the three failure traces above, including unread service requests and
  nested batches. Stop before wait registration and while blocked; verify no lost
  wakeup. Test both orders of stop versus buffered and rendezvous commitment.
- Verify shared process-pool paths/keys survive job exit and Map free. Cover an
  explicitly private-pool result with normal export, separately owned error
  snapshots, void completions, and completion-result lifetime after handle free.
- Verify adopted unsent/undelivered Maps and native resources are reclaimed only
  after all participants finish. Do not use client cancellation as borrow completion.
- Run existing Scope, Map/Array, Context export, Thread, and ParallelMap tests
  relevant to these changed contracts. Preserve checked-in expectations unless
  a documented deliberate behavior change requires their update.

At implementation publication, use the root AGENTS.md delivery rules. The
change affects allocation/runtime hot paths, so use the existing performance
checkpoint and `tools/gate-state.py ensure agent-pr-check` on the final tree.
Do not claim constant-time movement from elapsed-time percentages: inspect
the reparent operation and establish that it does not walk payloads or descendants.
Implementation follows the authorized coordinated delivery above.

## Plan review

Existing callable lowering establishes typed invocation and capture representation;
reuse its adapters rather than adding a second callable system. Existing Thread
join establishes consuming export and handle state; reuse its result/error owners
and completion observation. Pool already establishes synchronized canonical lookup
and insertion; the new batch path selects the process pool rather than wrapping
Strings in per-message ownership helpers. No new graph validator rechecks lifetimes.

Channel synchronization establishes acceptance/delivery. Thread stop publication
and wait registration must coordinate with that boundary once; no channel-wide
failure state or second error owner is needed. A raw wakeup is insufficient without
pending state. Scope transfer needs owner links and synchronization because shared
workers can adopt while the consumer frees children; it does not inspect payloads.

Thread.run and its private handle storage are necessary to own partial startup and
stop-all-before-join cleanup. They replace repeated application failure handlers
and handle bookkeeping. No Thread links, task_scope, Producer endpoints, sender
analysis, or recursive transport exporter is added. Existing ParallelMap machinery
is preserved for compatibility, not claimed as a second implementation to expand.

The example uses ordinary lambdas, an Array of callables, one caller-owned worker
count, explicit close, Scope transfer, and existing Cleanup/defer conventions.
Reference capture is required only for the completion counter's binding; captured
Map handles still permit their agreed sole-writer use. Cleanup and joining finish
before channels and borrowed data leave scope. Process-pool memory retention is
explicit and unbounded by queue capacity; no performance improvement is claimed.

Proposed checks protect non-void Channel transport, exact tag constraints, legal
capacity, send-after-close, and native synchronization/lifetime safety. Existing
Var facts own tag checking. Stop-race, partial-startup, export-failure, and borrow
fixtures protect wrong successful completion, deadlocks, or premature destruction;
no new general AST, payload-graph, or lifetime validator is planned. Optional
constructor/tag defaults remain identified proposals, not silently agreed behavior.

Implementation must finish with authored-source and generated-diff review before
the existing publication proof. Gary has subsequently authorized implementation with one integration owner.
No runtime behavior or validation result is claimed from the illustrative example.
