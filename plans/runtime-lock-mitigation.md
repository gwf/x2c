# Remove unnecessary runtime synchronization

> Status: active - implemented; shared integration pending.
> Implementation and focused validation completed on 2026-10-29.
> Sections 1-7 are implemented. Section 8 was measured and retains FILE locks.
> Author stage-2 passed. Shared integration owns the final full gate and publication.
> No full gate ran in the implementation session.

## Result and boundaries

Remove empty, redundant, and ownership-unnecessary critical sections. Replace
standalone flag and sizing-hint mutex reads with atomic accesses. Reduce queue
notifications and move private Array mutation outside the shared monitor.

Preserve public signatures and layouts, canonical identity, named diagnostics,
accounting opt-in behavior, callback serialization, stop outcomes, Channel
commitment and ownership, and shutdown ordering. Callers acquire no new
obligations. Do not add a refill service, per-Channel locks, reader counters,
new allocation modes, or a configurable public locking API.

The initial audit compared authored `43c1e717e` with `origin/dev` at
`5743c98a10da2df10e04251b83b4cc7efc74a00c`. Mutex-owning runtime source was
identical. HTTP differed only in unrelated formatting. Recheck touched owners
at implementation start; preserve intervening intended changes. The plan
branch starts at `e794af733cbb5eb6e4e65849185f13945a16ee13`; runtime owners
remain unchanged from that audit baseline.

A temporary probe against the unchanged runtime, with accounting disabled,
observed these mutex acquisitions:

| Operation | Before | Intended after |
| --- | ---: | ---: |
| Pool.malloc of 1,024 bytes | 2 | 1, retaining the Pool owner lock |
| Destroy an empty unnamed Scope | 1 | 0 |
| Filtered global log event | 2 | 1 |
| Free a fresh unused Channel | 2 | 0, after Scope and Channel changes |

These are operation counts, not CPU savings or contention measurements. The
prior naming-disabled benchmark used a private Scope object; naming removal
was not shipped. This plan preserves names while removing unnamed work.

## Changes

### 1. Pool accounting and initialized storage

Owners: `lib/pool/storage.x`, `lib/pool/interning.x`.

- For allocations above 512 bytes, enter the storage mutex for traffic
  accounting only when `Scope.accounting_enabled()` is true. The accounting
  mode is fixed at initialization. Keep the Pool owner lock around its
  mutable Scope allocation links.
- Give `_storage_initialize` an acquire-load fast path on
  `pool_storage_ready`. Retain the existing storage mutex and a second atomic
  check on the slow path. Publish ready with a release store only after
  shutdown-hook registration succeeds. Failure leaves initialization retryable.
  Convert the quiescent shutdown reset to an atomic store too. Do not replace
  this with an initialization primitive that changes Error transfer/retry.
- Read and write `child_capacity` with relaxed atomics after publication. It
  is only a standalone allocation-size hint, not publication of its child's
  table. This removes `_child_capacity`'s read lock. Keep release's parent
  lock because block reparenting still mutates parent storage.

No Pool representation change is needed. Initialization, registry/depot,
slot-list, shared nonroot table and ownership protections remain in place.

### 2. Scope names without unnamed registry traffic

Owners: `lib/scope/scope.x`, `regions.x`, `accounting.x`.

Allocate a module-private `ScopeRecord` containing the existing public
`struct Scope` as its first member, followed by one `ScopeName` pointer.
Return the address of the public first member as before. Only `_new_scope`
creates valid Scope handles; `_destroy_chain` is the matching destruction
owner. Do not add fields to public `struct Scope` or reuse its live links.

This increases requested control-record bytes from 56 to 64 on a 64-bit
host: one pointer per Scope, with no extra allocation for unnamed scopes.
The public type's size, alignment, offsets and signatures remain unchanged.
Actual allocator footprint must be measured rather than inferred from those
requested sizes.

- Initialize the private pointer to NULL for unnamed scopes. Creation and
  destruction then do no name-registry lookup or locking.
- For named scopes, fully allocate the existing registry node and copied name
  before publishing the completed Scope. Store its node pointer in the private
  record. Preserve allocation failure cleanup for every partial resource.
- Make `Scope.name` read this immutable per-Scope pointer directly, including
  `Scope.name(NULL) == NULL`. The returned name keeps its existing lifetime;
  destruction must already have exclusive access to the Scope.
- On named destruction, unlink the node under the metadata mutex, then free
  the detached node/name outside it. Keep the existing named registry and
  exit-time report. Do not add a second index or another lifetime owner.
- Allocate control records through `_data_malloc` and destroy with `free`,
  preserving their existing accounting category. Keep raw name/node
  accounting and terminal registry cleanup balanced.

This private representation change is the main memory tradeoff in the plan.
It removes both unnamed destruction scans and `Scope.name` read locks while
retaining useful named diagnostics even when allocation accounting is off.

### 3. Channel destruction and buffered notifications

Owner: `lib/channel.x`.

`Channel.free` already requires all users and waiters to have finished. Set
`closed` locally before destroying its lifetime, preserving the ordering seen
by any owned-payload finalizers. Do not call synchronized `Channel.close` or
broadcast from this quiescent destruction path. Reuse the existing `_drop`
finalizer to drain owned storage and destroy native resources. Public close
retains its lock and wakeup behavior for live Channels.

For buffered Channels, broadcast on empty-to-nonempty enqueue and
full-to-not-full dequeue. Compute each transition under the existing monitor
using the old count. Retain broadcasts for close, Thread.stop, and rendezvous
commitment. Keep **broadcast**, not signal: senders and receivers share the
same condition variable, and signaling an ineligible class can strand work.
No waiter counters or second condition variable are needed.

All predicate checks, wait registration, queue mutation, and commitment stay
under the existing completion monitor. A waiter can newly sleep only when its
predicate is false; the transition broadcast wakes every earlier waiter. An
unbounded queue never has blocked capacity senders to wake on dequeue.

### 4. Standalone stop flags

Owners: `lib/net.x`, `lib/http.x`, `lib/thread.x`.

Use release stores and acquire loads on the existing integer stop fields.
Initialize zero before publishing each object. Audit every access so no plain
concurrent access remains.

- `Listener.stop` publishes its independent flag without the global completion
  mutex. HTTP checks the flag atomically after a response. Check `!keep` first
  to skip a stop read when the connection already must close.
- The listener poll reads its flag and Thread stop state without acquiring
  the completion mutex. Preserve the 50 ms polling bound and descriptor
  lifetime: close still follows completion of the accepting thread.
- `Thread.stop` retains the monitor around flag publication, waiting-pointer
  inspection, and wakeup. `x2c_thread_wait_stopped` atomically reads the flag;
  `_batch_check_stop` no longer locks solely to call it.
- Update internal comments to distinguish atomic stop polling from waiting
  registration. Registration and queue commits still require the monitor.

Atomic polling does not interrupt blocking I/O, transfer a borrowed object's
ownership, acknowledge completion, or change commit-before-later-stop rules.

### 5. Private wait_any Array mutation

Owner: `lib/thread.x`.

Have `_wait_any` select and return an index while holding the monitor, or -1
for cancellation. Unlock before removing that index from the caller-owned
`pending` Array. Its existing contract guarantees exclusive Array and handle
access. Preserve first-finished-in-Array-order selection, failure reporting,
handle validity and cancellation behavior. Selection commits under the lock;
a later stop does not retract it. Do not move shared ParallelMap ready queues
outside their lock: those have different ownership.

### 6. Logger entry and construction

Owner: `lib/logger.x`.

Move the current delivery body into one private lock-held helper. Keep the
synchronized instance and global entry wrappers; both call that helper
directly. The global wrapper holds one lock from selecting `global_logger`
through filtering and delivery, so its pointer and sinks cannot be retired
between selection and use. Already-locked Error observer and pending-shutdown
delivery paths can call the same helper directly.

Remove `synchronized` from `Logger.new`: it initializes unpublished private
state and only reads caller-local allocation state and pure level metadata.
Scope and Pool retain their own necessary synchronization.

Keep the recursive logger mutex for user callback reentry, mutable settings,
sink lists, sequencing, lifecycle and flush. Do not turn this into a campaign
to replace every cold nested lifecycle call with another helper. HTTP already
uses the instance logging path, so global-wrapper savings must not be claimed
as savings on its access-log path.

### 7. Descriptor frozen-status reads

Owner: `lib/dispatch.x`; caller: `lib/var/classes.x`.

Make `x2c_descriptor_registration_frozen` an acquire load. The successful
native-start end publishes the frozen flag with a release store. Route the
registration guards through the getter so every concurrent access is atomic.
Keep native-start exclusion and registration mutation under the descriptor
mutex. Failed startup leaves registration open. No new public helper or
signature is needed. This is a cold registration/status improvement;
descriptor dispatch already has lock-free reads.

### 8. Conditional worker-local stdio case

Owners: `lib/http.x`, with `lib/file.x` as a compatibility boundary.

Account for this audit candidate without assuming an uncontended FILE lock
is a measured bottleneck. The server worker exclusively reads its Socket
input, but public `HttpRequest.read` accepts an arbitrary File and generic
`File.readline_into` promises a locked logical line.

Measure the remaining FILE-lock cost after the changes above using a
source/disassembly trace or focused profile. If the exclusive server path has
material cost, share one parser body behind the public locked entry and an
internal exclusive-input entry. Keep one line scanner: its public wrapper
locks/unlocks; the private server entry can use the same scanner without that
wrapper. Preserve all framing, EOF, limits, failure cleanup and timeout behavior.
Do not change generic File semantics, add public flags, or create a second
HTTP parser. Other stdio operations can still take implicit locks.

If the profile cannot attribute a meaningful remaining cost to these locks,
record that result and retain them. This is an explicit measured disposition
of a conditional candidate, not a claim that its overhead was eliminated.

## Work sequence and verification

Use the existing subagents for independent implementation and review, under
`orchestrate-x2c-work`. Give implementation workers isolated worktrees at one
recorded current-dev revision and `worker/private` context. No worker runs a
full gate, merges dev, or pushes.

1. Run three independent workstreams: Pool/Scope (1-2),
   Channel/Thread/HTTP/net (3-5), and Logger/dispatch (6-7). Each worker owns
   its listed source and matching test files. The transport worker owns
   `test-thread.x`; the descriptor worker reuses its existing startup tests
   and hands any missing coverage to that owner before final integration.
   Keep transport changes together because Thread.stop and Channel commitment
   share a protocol.
2. Extend the existing focused tests only where behavior changes. Combine
   the work, review source and generated-C atomics/public layouts, and fix
   findings before broad publication validation.
3. Repeat temporary operation-count probes with accounting off and on. Keep
   instrumentation outside shipped code. Extend the probe to initialized Pool
   creation, listener/Thread polls and descriptor status. Separate mutex
   acquisitions, recursive acquisitions, broadcasts, allocations and bytes.
4. Run the matched 64-client Notes lookup comparison for database-mutex and
   database-thread servers against Go. Keep naming behavior and accounting
   settings identical between before/after binaries. Do not use the old
   naming-disabled Scope object as one side of this comparison. Include
   throughput, CPU/request, total server CPU, latency and peak RSS; retain all
   samples, hashes and ordering. Report background noise as previously agreed.
5. Disposition the conditional stdio case using the remaining profile.
   Benchmark an isolated follow-up only if that evidence warrants its change.
6. Review and commit the coherent authored result. Run author stage-2 on the
   submitted code head. Submit pinned ready PRs to the shared integrator,
   with focused evidence and any explicit dependencies. The integrator owns
   final bootstrap/docs generation, the existing publication gate and the
   existing compiler performance checkpoint. Do not gate each workstream.

Focused checks use the existing suites and examples:

- Pool/Scope/Context/ownership with accounting both disabled and enabled:
  large allocations and exact counters; named/unnamed/NULL name queries;
  copied-name lifetime; nested/retained/transferred scopes; finalizers and
  shutdown leak reports; shared Pool creation and child sizing.
- Channel/Thread/wait_any: bounded and unbounded many-producer/many-consumer
  progress; close/drain; owned payload cleanup; quiescent free; stopped
  waiters; rendezvous commitment; startup failure; cancellation races;
  completed-worker order and private Array removal. Preserve existing wait
  fixtures and add only missing transition cases.
- Logger/descriptor: filtered events, no-allocation paths, sequence/order,
  recursive callbacks, sink-mutation rejection, Error observers, flush and
  global replacement/shutdown; successful registration freeze and failed
  startup retry. Confirm global logging takes one delivery lock.
- HTTP/net: parser and framing tests; loopback, keepalive stop, Listener.stop
  and Thread.stop cancellation. Run both Notes API/concurrency/restart/store
  suites and database-thread error/queued-shutdown checks.

No new recurring gate, permanent lock profiler, benchmark framework, or
unrelated test suite is proposed. Use the existing publication workflow.
Report compiler instruction cost separately from server CPU and throughput.
A regression triggers focused attribution, not silent omission of a workstream
or repeated samples selected for favorable results.

## Locks deliberately retained

Nonroot Pool tables and block ownership remain mutable and can be shared.
The block page index can grow and release its old storage. Scope ownership
links still require caller exclusivity. None of those locks can disappear
because a caller happens to hold a thread-local Context.

Channel queue/commit/wait registration stays synchronized. Logger mutable
state and callback delivery stay serialized. Descriptor overflow cell storage
can grow after registration freezes and keeps its mutex. Match sites, catch
sites and initialized static guards already have published fast paths; retain
their first-publication locks. Third-party library internal locks were not
audited and are outside this plan.

## Plan review

The owning contracts already establish quiescent Channel destruction,
exclusive wait_any Array access, unpublished Logger construction and valid
allocator-created Scope handles. The changes consume those guarantees without
rechecking them or imposing new caller obligations. Atomic flags do not
replace queue commitment or lifetime ownership.

Reuse the existing Scope name registry, Channel finalizer, logger delivery
body, and initialization/error paths. Delete empty accounting sections,
recursive entry calls, unnecessary notifications and standalone read locks.
The only new persistent representation is one private pointer per Scope;
there is no spare public field, and retaining names requires local membership
information. The private wrapper preserves ABI and adds no native allocation.
The logger helper gives the existing body one owner; atomics apply to existing
fields. The conditional HTTP path must share its parser and scanner.

The result stays ordinary runtime code rather than adding a synchronization
framework. No validators, dedicated diagnostics, or caller-side locking modes
are added. Test extensions protect actual wakeup, cancellation, ownership,
identity, accounting and callback behavior. Failure cleanup protects partial
Scope construction; it does not add downstream checks for valid Scope handles.

## Execution evidence

Implementation started at current `origin/dev`
`fa1cf22fee3d30e72df6939ef8ba36a60e133269`, after the plan PR merged.
Three isolated workers completed the listed source groups with private
handoffs. The combined code head is `493f1a01c`.

The [execution report](../examples/apps/notes/bench/reports/2026-10-29-runtime-locks/README.md)
records operation counts, actual Scope footprint, both accounting modes,
combined checks, author stage-2, matched Notes samples, stdio disposition and
coverage limits. Names remain enabled throughout the Notes comparison.
Temporary instrumentation remains outside shipped sources.

Scope construction keeps its preinitialization boundary: native allocation
failures free partial resources before raising, without requiring Error
cleanup. Listener representation reads the stop flag atomically too.
Shared integration still owns final generated artifacts, the full gate,
compiler performance checkpoint and publication. Keep this plan active until
that delivery is recorded.
