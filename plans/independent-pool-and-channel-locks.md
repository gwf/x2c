# Implementation plan: independent Pool and Channel synchronization

> Status: blocked - current implementation fails mandatory performance acceptance.
> Researched against `66a119db5e44723bf7763f603b684b7dd9091ca2` on 2026-10-30.
> Implementation baseline: `56fd5ecc1518f40ac46f2c21f50936ae4ab53f93`.
> Pool, Channel, and Thread runtime owners are unchanged between these revisions.
> Gary authorized monitored implementation and integration on 2026-10-30.
> Performance measurements and no reproducible regressions are mandatory
> before merging to dev. Any tradeoff requires Gary's explicit approval.
> Revised local runtime candidate: `bdb8cdbbd`. Nothing from this work has been pushed.
> Matched runtime measurements reproduce regressions. No tradeoff is approved.
> Design revision requested after measurement: see
> [the revised design](independent-locks-revised-design.md).
> That proposal replaces the accounting, index-builder, and Channel protocols
> below. The original design and execution record remain as failure evidence.
> Gary authorized the reviewed revision; measure previously failing workloads first.

## Result and contracts

Remove the process-wide lock from ordinary independent Pool operations and
all Channel send/receive operations. Where storage is genuinely shared, hold
its lock only for publication or list rewiring, never while waiting for a
Pool owner lock, allocating native backing storage, rebuilding an index, or
walking a released pool.

Preserve canonical identity, pointer-stable promotion, pool release order,
depot reuse, accounting opt-in and counter meanings, allocation failures,
Channel FIFO buffering, close/drain behavior, owned-send rollback, and
stop-versus-commit outcomes. Add no caller obligations or public API modes.
Preserve public runtime signatures and exposed layouts. Channel and Thread
records are private; their native resource footprint may grow.

This plan supersedes only the deliberate retention of Pool storage
synchronization and the exclusion of per-Channel locks in
`archive/runtime-lock-mitigation.md`. It does not reopen that plan's other changes.

## Pool: separate address classification, ownership, and depot transfer

Current owners are `lib/pool/storage.x`, `interning.x`, and `root-index.x`.
Today storage locking covers address lookup, owner-lock acquisition, block
refill, and entire release walks. Index lookup itself locks a candidate owner
in `_contains`. These are separate responsibilities.

### Address classification without a reader mutex

Keep the existing process-wide page index. Reuse the publication pattern of
the root canonical index: release-publish completed entries and acquire-read
them; retain superseded index arrays until quiescent shutdown.

Block addresses and backing extents are fixed until shutdown. Initialize
`bytes` once before registration, instead of rewriting it when leasing the
same block again. Classify a valid allocation by its immutable backing
extent. Do not read mutable owner, used bytes, or slot class to decide whether
the pointer is region-backed. The existing APIs supply valid allocation
addresses, not arbitrary pointers needing authentication. Large allocations
remain Scope-owned and cannot overlap retained native Pool blocks.

Publish a new block's registry/index membership before returning any slot.
Keep the allocation-failure fallback: publish the registry as immutable links
behind an atomic head. If the index becomes incomplete, lookup walks that
registry without a mutex. This fallback is linear, not constant time.
The readiness/completeness publication must ensure a reader cannot report a
false absence for an already-published allocation.

Owner lifetime remains a separate proof. `Pool.free` accepts an allocation
from the supplied pool's chain. That live pool and its ancestors cannot be
released during this use under existing release rules. Lock the owning pool
from that chain before modifying its free list; do not treat an arbitrary
owner pointer discovered in the registry as an independent lifetime grant.
Promotion can refer to storage still physically held by a descendant. Its
owner comparison must use atomic owner publication, without dereferencing a
possibly retired descendant. Preserve child-to-parent locking and delayed
promotion records. Audit every owner access for this distinction before
implementation; do not add refcounts or new caller restrictions as a shortcut.

### Refill and release

Preserve the existing per-Pool bump/free-list operation. An available block
needs only the Pool mutex. On refill, pop one block from the depot under its
short lock. If none exists, allocate backing storage outside shared locks,
register it, and install it under the destination Pool mutex. Recheck room
after preparation because another worker may have refilled the same pool;
return an unused candidate to the depot without leaking or double-registering
it. No shared depot/index lock may wait for a Pool mutex.

Release remains proportional to the pool's blocks and promotions, but none
of that walk holds the depot lock. Under the affected Pool locks, apply
promotions and prepare survivor blocks. Build private discarded-block chains
for the five existing depot sizes, recording tails and count/byte deltas.
Under the depot lock, splice at most five chains and apply their totals.
Destroy detached Scope storage outside the depot lock.

Prepare survivor free lists before attaching them to the parent. Retain the
existing affected child/parent locks during survivor preparation and transfer
in this implementation. Narrowing those owner locks is outside this change.
Never claim shared-parent promotion is independent work. Keep it out of the
global depot section.

### Index writes and statistics

Separate index publication from depot exchange. Allocate and rebuild a larger
index outside its writer mutex. Capture the current table and publication
version, copy acquire-published entries, then validate that version under the
mutex. Publish only if unchanged; otherwise discard the unpublished candidate
and retry. Old published tables remain alive. Registering a new block publishes
at most two page entries, registry linkage, and a version increment.

Hash probing is expected short, not worst-case constant. Rebuild retries are
not bounded under adversarial concurrent growth. No allocation, rehash, or
free of a rejected candidate belongs inside the publication lock. This is an
explicit tradeoff for keeping readers independent without a reclamation system.

Accounting must not recreate the removed global lock on every allocation.
Use opt-in atomic traffic counters, preserving requested-byte saturation and
zero traffic counters when accounting is disabled. This still creates shared
cache-line traffic when accounting is enabled. Keep structural depot counters
under the depot lock and registration counters under their publication owner.
`Pool.stats` must preserve meanings and exact quiescent results. Take Pool
locks before shared accounting snapshots; never retain the old storage-to-Pool
lock order. Take index publication before depot when a structural snapshot
needs both locks. No other path may take them in reverse order. Never call
allocation or user callbacks inside either shared section.

Costs: old geometrically grown index versions retain approximately one extra
current table's capacity in total, plus version metadata. Concurrent rebuild
candidates add transient memory. No per-slot headers, block alignment changes,
per-pool address indexes, or additional fields in public Pool records.

## Channel: one queue mutex, persistent per-thread wake state

Current owners are `lib/channel.x` and `lib/thread.x`. A per-Channel mutex
alone is insufficient: stop publication must still be ordered against both
participants' rendezvous commitment, and sleeping must not lose a stop wakeup.

Give each Channel one queue mutex. Give each managed Thread a persistent wait
mutex and condition, constructed before native startup and destroyed at
`Thread.free`. An unmanaged caller has no stop gate on its immediate path.
If it must block, prepare a stack-owned wait mutex and condition outside the
Channel lock, then reacquire the Channel and recheck before publishing its
wait record. Destroy those resources after unlinking and leaving the queue
lock. This requires no new native-thread cleanup obligation. Keep native
initialization failure cleanup complete. Stop never stores or dereferences
a borrowed Channel pointer.

Use the existing intrusive sender/receiver lists for buffered waiters as well
as rendezvous waiters. One native thread can have only one active synchronous
Channel wait; its record needs no heap allocation.

The lock order is Channel queue mutex, then participant wait mutexes in one
stable total order. A portable implementation can order distinct wait records
by their integer address representation. No path acquires a Channel mutex
while holding a wait mutex.

1. Prepare a buffered message or owned payload before locking the Channel,
   as today. For a buffered commit, lock the Channel and the managed caller's
   wait mutex before the final stop check and queue commitment.
2. A rendezvous selects its peer under the Channel mutex before acquiring
   either participant's wait mutex. Acquire the participating mutexes in the
   total order, recheck both stop flags, copy the representation, unlink the
   waiter, and mark commitment before releasing them. Never retain a caller
   wait mutex while subsequently acquiring a lower-ordered peer mutex.
   An immediate unmanaged caller has no wait mutex to acquire; a queued
   unmanaged peer has its stack-owned wait mutex.
3. A blocked caller links its record under the Channel lock. Holding its wait
   mutex, it rechecks stop and readiness, releases the Channel lock, and enters
   `pthread_cond_wait` on its own condition and wait mutex.
4. On waking, release the wait mutex before reacquiring the Channel mutex.
   Recheck predicates under their owners. Unlink a pending record exactly once
   before returning or raising; a peer may already have unlinked a committed
   or cancelled record, so record that membership explicitly.
5. Signal a peer's private condition while holding its wait mutex. This closes
   the check-to-sleep gap: a notifier cannot signal between the final check
   and the wait's atomic mutex release.

Payload adoption, rollback, destruction, native message allocation/free, and
Error dispatch stay outside all queue/wait locks.

### Bounded queue work and notification

Wake an eligible sender/receiver for a newly available opportunity. A woken
waiter hands notification onward when work remains, including if it cancels
or another caller consumes the opportunity first. Cancellation must not strand
an available item or capacity. Preserve buffered message FIFO; the book
promises no fairness among competing callers.

Remove and notify at most one stopped head per locked attempt, then unlock
and retry. Replace `_live_wait`'s potentially unbounded stopped-waiter scan.
Close sets the flag and wakes the two list heads. Departing waiters propagate
notification until both lists drain. This keeps close's direct queue work
bounded, but total wakeup work remains proportional to waiter count and can
be delayed by scheduling. Do not describe it as constant-time completion.

### Stop and the existing completion monitor

For this change, retain Thread's completion monitor for `wait_any` and the
parallel scheduler. `Thread.stop` takes completion mutex then target wait
mutex, publishes stop and signals the target, releases its wait mutex, and
performs the existing completion notification. Preserve legacy completion
wait registration while it is still used. Channel paths never take the
completion mutex. No wait-mutex holder may acquire the completion mutex.

This preserves completion selection ordering and avoids expanding the task
into scheduler redesign. Stop requests still share that short global section;
ordinary independent Channel traffic does not. Wait-any's existing Array scan
and parallel scheduling remain separate contention candidates.

Stop before commitment prevents the operation. Commitment before stop remains
successful. In rendezvous, holding both wait mutexes makes that decision
indivisible for both participants. Stop before registration persists in the
flag; stop during sleep signals the persistent condition. Stop after unlink
cannot touch freed Channel storage. Existing quiescent Channel destruction
and live Thread-handle requirements remain sufficient.

Costs: one mutex per Channel, a mutex/condition per Thread, and additional
waiter bookkeeping. Uncontended operations acquire more local mutexes than
today's one global mutex. A rendezvous needs both participant mutexes. Measure
that cost against parallel scaling; do not infer a single-thread speedup.

## Implementation sequence

Keep Pool and
Channel changes as two coherent checkpoints, then validate their combined
tree. They do not require separate publication gates or PRs.

### 1. Establish the baseline and affected contracts

Read current root instructions, `agents/quick-start.md`,
`agents/performance-checkpoints.md`, and `unittest/AGENTS.md`. Record the
starting revision and worktree changes. Recheck the source owners against the
research revision and preserve intervening intended changes. Use
`execute-x2c-plan` for implementation. If delegating implementation, load
`orchestrate-x2c-work` first and give workers isolated private worktrees.

Build the shipped bootstrap with `make build-safe` before using `builds/0`
in a fresh worktree. Capture full logs under `debug/`. Establish unchanged
focused-suite and performance baselines before modifying runtime owners.
Keep temporary probes and binaries outside tracked source. Record workload,
revision, accounting mode, worker count, and pool selection with each result.

### 2. Implement Pool address publication

Owners: `lib/pool/storage.x`; reference implementation:
`lib/pool/root-index.x`. Preserve `lib/pool/pool.x`'s exposed layouts.

- Replace mutable reader-visible index storage with published index versions
  and atomic slot publication. Initialize immutable block extents before
  registry publication. Keep registry links immutable after publication.
- Implement off-lock replacement construction and version-checked publication.
  Release rejected unpublished candidates outside the writer lock. Retire
  published versions only at quiescent shutdown.
- Preserve allocation-failure fallback. On a lookup miss, account for index
  replacement and incomplete-index publication before concluding absence.
  Audit the happens-before chain from block registration to returned pointer.
- Replace `_contains`' owner/class/used checks with immutable extent lookup.
  Convert concurrent owner accesses consistently to atomic accesses where
  promotion can observe an ownership transfer. Keep free-owner lifetime
  justified by the supplied live chain, as described above.
- Verify growth, fallback, ancestor free, and multi-level promotion before
  removing the remaining broad storage sections.

Done when free/promotion address lookup acquires no storage or owner mutex,
and all index versions and fallback entries remain valid through shutdown.

### 3. Implement Pool refill, release, and accounting

Owners: `lib/pool/storage.x`, `lib/pool/interning.x`, and initialization
helpers in `lib/pool/threads.x` where needed. Extend `unittest/test-pool.x`.

- Split index publication and depot exchange ownership. Preserve the
  no-worker lock bypass and initialization retry behavior.
- Implement prepared refill candidates, room rechecks, and return of unused
  candidates. Keep native backing allocation outside shared locks.
- Replace `_release_blocks`' global locked walk with private per-size chains
  and aggregate totals. Splice them under the depot lock. Preserve survivor
  preparation under existing owner locks and Scope destruction afterward.
- Move opt-in traffic accounting to atomic operations, including saturating
  requested bytes. Preserve structural counter identities during candidate
  acquisition, installation, return, and release. Update `Pool.stats` to the
  declared lock order.
- Remove obsolete broad storage-lock helpers and comments once their callers
  use the new owners. Preserve all documented failures and shutdown hooks.

Done when an existing-block allocation and a valid free take only their Pool
owner mutex with accounting off; refill never waits for an owner under a
shared lock; and release's depot section contains at most five chain splices.
Run the focused Pool checks and compare Pool workloads with the baseline.

### 4. Implement Channel and Thread wait resources together

Owners: `lib/channel.x`, `lib/thread.x`; tests: `unittest/test-channel.x` and
`unittest/test-thread.x`. These files form one change because stop and
commitment are one protocol.

- Add the private Channel mutex and managed Thread wait mutex/condition.
  Initialize before publication; destroy only at existing quiescent lifetime
  boundaries. Cover partial initialization and failed native worker startup.
- Add operation-local wait resources for unmanaged blocking callers. Prepare
  them outside the Channel lock and destroy them after unlinking. Do not
  introduce a native-thread destructor requirement.
- Extend the existing waiter record with explicit membership and wake-state
  fields needed by buffered and rendezvous waits. Assign every field one
  synchronization owner; distinguish queue membership from commitment.
- Implement Channel-to-ordered-wait-mutex acquisition and the sleep handoff.
  Select rendezvous peers before taking participant mutexes. Never reacquire
  a Channel or completion mutex while holding a wait mutex.
- Route `Thread.stop` through completion-to-target-wait ordering. Preserve
  legacy completion waits and their selection-before-later-stop behavior.
  Remove Channel usage of the global completion wait helpers without changing
  public runtime signatures or unrelated scheduler behavior.

### 5. Complete Channel notification and commitment paths

- Move buffered, rendezvous, and close state changes under the Channel mutex.
  Perform stop checks and commitment under the relevant participant mutexes.
- Link buffered waiters into the sender/receiver lists. Implement targeted
  notification and handoff after success, cancellation, and lost opportunity.
  A stopped head is removed and signaled once before unlocking and retrying.
- Implement close notification through the two waiter lists. Preserve draining
  of accepted messages and rejection of unaccepted sends. Remove the old
  Channel-wide condition variable and broadcast paths once unused.
- Keep payload preparation, allocation, adoption, rollback, destruction, and
  Error dispatch outside queue/wait locks. Check every exit for exactly-once
  unlinking and ownership disposition.

Done when independent Channels share no queue lock, stop cannot be lost at
sleep entry, and both participants agree on each rendezvous outcome. Run the
focused Channel/Thread checks and compare Channel workloads with the baseline.

### 6. Verify the combined implementation and update the book

Run the validation below on the combined tree. Review the composed lock graph,
not just each component separately. Confirm Channel preparation and cleanup
can use Pool operations without introducing a reverse lock edge. Retain all
benchmark samples and attribute regressions with focused probes; do not select
only favorable samples or claim measured improvement from lock counts alone.

Update authoritative prose in `docs/src/guide/channels.md` and
`docs/src/guide/contexts-and-threads.md` where implementation descriptions
changed. Update source API comments where needed. Preserve the documented
contracts. Regenerate derived module documentation through repository targets
when applicable; never hand-edit generated runtime or bootstrap artifacts.

### 7. Review and fix the completed authored diff

Review every lock acquisition, publication, resource lifetime, error exit,
counter update, and changed ABI boundary. Compare the result with this plan's
full scope. Remove duplicate state or helpers that no longer earn their cost.
Fix findings and repeat only affected focused checks before publication
validation. Record evidence and remaining limitations in this plan.

## Validation

Use existing Pool, Channel, Thread, Context, and ownership suites, extending
only missing cases. No new recurring gate or benchmark framework.

- Pool: small/large allocation, free from a live ancestor chain, multi-level
  pointer-stable promotion, concurrent shared-parent activity, depot reuse,
  index growth/publication, fallback after index allocation failure, shutdown,
  and accounting off/on including saturation and quiescent counter identities.
- Channel: buffered FIFO, bounded/unbounded progress, rendezvous, close/drain,
  stop before sleep, simultaneous peer stops, committed-before-stop success,
  cancelled-head notification handoff, owned rollback/adoption/destruction,
  initialization failure, and unmanaged-call wait-resource cleanup.
- Inspect every lock edge and native-resource lifetime. Use temporary
  controlled scheduling probes for the commit/sleep/publication races; random
  stress alone does not establish these protocols.
- Compare unchanged baseline and proposal at 1, 2, 4, and 8 workers: independent
  pools with reuse/refill/release; shared pools separately; independent Channel
  pairs; one shared Channel separately; buffered and rendezvous workloads.
  Hold work, accounting mode, and pool selection constant. Report operations
  per second, CPU per operation, wait/hold duration, and peak memory separately.
  Include the existing compiler performance checkpoint because single-process
  allocation and index memory also change.
- Review the authored and generated diff before the existing delivery checks.
  The acceptance requirements below apply before merging to dev.

## Mandatory performance acceptance

Before final acceptance or merging to `dev`, complete the matched baseline
and candidate measurements specified above, including independent and shared
Pool/Channel workloads, single-worker costs, both accounting modes, memory,
and the existing compiler performance checkpoint. Record exact revisions,
commands, raw samples, host/load conditions, and results. Missing, failed, or
inconclusive measurements do not establish acceptance.

Do not merge with a reproducible performance regression against the matched
baseline. Confirm suspected regressions with alternating same-host reruns
under comparable quiet conditions, distinguishing measurement noise from a
repeatable change. Fix a confirmed regression and remeasure, or obtain Gary's
explicit approval for the specific measured tradeoff before merging. Gains
in another workload do not waive this requirement. This includes increased
single-worker cost and retained memory; design discussion of an expected cost
is not approval of its measured magnitude.

This task-specific requirement overrides the advisory-only performance policy
in `agents/performance-checkpoints.md` for this change. It does not add a new
repository-wide recurring gate. A correctness gate pass is necessary but does
not establish performance acceptance.

The orchestrator owns host resource scheduling. Workers may edit and review
in parallel, but must request a build/test slot before running CPU-heavy work.
Run only one such job at a time. Measurements require an exclusive quiet
window with all owned builds, tests, and profilers stopped. Inspect unrelated
host activity before measuring; defer measurements rather than stopping work
owned by someone else. Keep worker job counts bounded and record contention
that invalidates a sample. Workers never run publication gates or independent
performance checkpoints.

## Delivery after implementation

Use the executing session's explicit delivery choice. No shared-integrator
mode is inherited from the older mitigation plan. With no later override,
the repository default is direct delivery by the implementing parent.

For direct delivery, establish `individual/direct` context, or
`orchestrator/direct` when collecting private workers. Fetch and integrate
current `origin/dev`, review the integrated authored diff, and run
`git diff --check`. Complete the existing performance checkpoint for this
coherent runtime batch. Run `tools/gate-state.py ensure agent-pr-check` on the
final tree; that command owns publication bootstrap refresh and broad checks.
Review generated deltas and ensure the gate again if the validated tree
changes. Publish only to `HEAD:refs/heads/dev` after successful correctness and
mandatory performance acceptance. An integrator must enforce the same rule.

If Gary explicitly selects the shared integrator, use the existing submission
workflow instead: focused evidence and `make stage-2` on the combined tree,
then a pinned ready PR through `tools/integrate-dev.py submit`. The integrator
owns final artifacts, performance work, and the publication gate. Do not run
both delivery workflows. A later local-only or review-stop instruction wins.

Report Pool and Channel outcomes separately, including contention measurements,
single-worker costs, retained memory, and any unresolved limits. Mark the plan
complete only after the requested delivery is verified. A reproducible
regression without Gary's approval blocks merging, including integrator delivery.

## Design review

The implementation reuses Pool block lifetime, the root index's publication model,
existing pool owner locks, intrusive Channel lists, and Thread lifecycle.
It deletes the broad storage-lock dependency and Channel dependence on the
completion monitor. It does not introduce a generic lock framework, a refill
service, reclamation counters, public locking choices, or a second allocator.

The selected architectural costs are retained index versions,
private native-resource growth, and notification handoff in place of Channel
broadcasts. Owner-lifetime and stop-commit reasoning must survive implementation
review. A conflict must be resolved here, not repaired by imposing new caller
obligations. Performance benefits remain hypotheses until measured.

## Execution evidence: 2026-10-30

Two Sol workers implemented isolated, nonoverlapping changes from local plan
commit `b4c0b48aa`. The orchestrator integrated their private checkpoints:

| Work | Worker checkpoint | Integrated checkpoint |
| --- | --- | --- |
| Pool storage and tests | `c27615499` | `7c9852c15` |
| Channel/Thread, tests, and guide text | `d7fd0f718` | `a18615ad4` |
| Restore temporary waiter pointers without region warnings | `d4a88e62c` | `989978baf` |

The orchestrator serialized all owned builds, test runs, and native probes.
Builds used `BUILD_JOBS=2` and `make -j2`. Workers never ran a publication gate,
performance checkpoint, or push. Source review ran alongside builds without
starting additional compute jobs.

Baseline runtime `56fd5ecc1` passed the selected Pool, Channel, Thread,
wait-any, parallel-map, Context, and storage-ownership suites with accounting
off and on: 119 tests and 1,252 assertions per mode. The final integrated
candidate passed the same selected suites with the new tests: 122 tests and
1,352 assertions per mode, with no failures or skips. Final logs in the
orchestrator worktree are `debug/locks-final-unittest-build.log` and
`debug/locks-final-focused-{off,on}.log`. The final incremental compiler build
is recorded in `debug/locks-restored-build.log`.

Pool worker evidence additionally covers forced index allocation failure,
registry fallback, requested-byte saturation, and a controlled index-version
change between copy and validation. The retry probe verified one rejected
candidate free and valid lookup/free for old and newly registered blocks.
Logs remain under `/tmp/x2c-locks-ec97-pool/debug/` as
`pool-internals{,-build}.log` and `pool-retry{,-build}.log`.

Channel worker evidence includes 125 tests and 1,030 assertions in its broader
selected suite set. Temporary native fault probes covered initialization and
startup failures, unmanaged owned-send rollback, and stop at condition-wait
entry. Final probe result: `caught=5 mutex_live=0 cond_live=0`. The restored
pointer form translates without the initial region warnings. Logs remain
under `/tmp/x2c-locks-ec97-channel/debug/channel-restored-*.log`. Temporary
instrumentation was not added to shipped source.

Each worker performed a bounded source review of the other's synchronization
changes. No concrete new protocol defect was found. These source reviews do
not establish performance acceptance or substitute for the publication gate.

At the first local checkpoint, matched benchmark binaries and a runner were prepared in
the orchestrator's `.context/lock-contention/`. Only short baseline harness
smoke runs had executed; no comparative performance results were claimed then.
Repeated host checks found sustained unrelated system-monitor and VM load.
A quiet measurement window was requested. No unrelated processes were
stopped. Both workers are now idle and hold no compute slot.

Gary subsequently supplied the quiet window. The
[performance evidence](reference/independent-lock-performance-2026-10-30.md)
records the full matrix, a narrow Channel follow-up (`bdb8cdbbd`, worker
`9680cd97a`), and longer confirmation runs. Independent accounting-off paths
improve, but same-worker/shared Channels and accounting-on Pools regress.
The growth workload also has a larger peak memory footprint.

Remaining before any dev merge: a revised design and implementation that
resolve the reproduced regressions, or Gary's explicit approval of each
measured tradeoff; remaining performance/lock-duration evidence; current-dev
integration and final authored/generated review; and the publication gate.
No compiler performance checkpoint, full publication gate, or push has run.
The current implementation remains local and is not accepted for merging.
