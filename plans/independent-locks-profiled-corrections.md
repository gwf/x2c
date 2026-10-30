# Small corrections proposed from the lock profiles

> Status: Pool fast path and Channel changes implemented locally; acceptance fails.
> Based on the unchanged runtime `a6be0e6c49a995aed7d097a526235b2ef12e4c54`.
> Measured runtime after sections 1 and 2: `360aab57fbf1fa46343ad514514fb3898dc40c5b`.
> The index proposal explicitly reintroduces a short shared lookup lock.
> That changes the earlier lock-free classification decision and is not approved.
> No reproducible regression may merge to dev. Every tradeoff requires Gary's
> explicit approval; design review is not performance acceptance.
> Gary authorized sections 1 and 2 only, with original-baseline measurements.
> Section 3 is not authorized; retain the current index unchanged.

The [profiles](reference/independent-lock-profile-2026-10-30.md) identified three
bounded corrections. Keep the working per-Pool counters, separate depot
transfers, immutable block extents, and tested stop/commit lifetime protocol.
Do not add another synchronization or reclamation framework.

## 1. Restore the small Pool allocation path

Measured problem: ordinary accounting-off bump allocation executes 93 emitted
ARM64 instructions instead of 72. General refill/index setup and spills occur
even when the current block has room. The 24.7 million common-path calls explain
almost all of the additional 513 million instructions in the release workload.
Native lock counts did not increase.

Restore an explicit accounting-off immediate path in `_small_malloc`: acquire
the Pool owner, inspect its current block, take a free/bump slot with accounting
disabled, unlock, and return. Preserve a small immediate path for accounting-on
allocations using the same slot primitive and private owner-serialized counters.
Only a miss enters the existing prepare/recheck/refill algorithm.

Keep refill out of line with a local `noinline` attribute, using the repository's
existing raw native-specifier mechanism. Do not mark ordinary accounted
allocation cold, change compiler-wide optimization, or add a new allocation mode.
Reuse slot arithmetic and counter updates; do not duplicate their algorithms.
Refill still prepares native backing outside owner/shared locks, then rechecks
under the owner lock before installing it or returning a surplus block.

Expected structural result: existing-block hits cannot pay inlined index-builder
setup. The native assembly, not source appearance, must establish that result.
No public layout, failure/counting point, ownership, or locking rule changes.
Accounting-on single-worker costs and refill-heavy workloads still require
measurement; a new call boundary is not assumed free.

## 2. Remove Channel dispatch overhead and restore baseline notification policy

Measured problems: registration helpers and split owner/stop checks add CPU on
immediate operations; shared waits grow longer despite equal explicit lock
counts. Buffered notification counts also increase. The profiles locate the
handoff cost but do not establish its exact kernel scheduling cause.

Retain the proven two-CAS registration protocol and completion acknowledgement.
Make only these connected changes:

- Combine caller-owner lookup and registration into one Thread helper. Return
  success and the borrowed owner token. It performs the existing TLS lookup
  and registration CAS once, rather than crossing the Thread boundary twice.
- Use specialized buffered send and receive loops. Reuse current queue-node
  operations and owned-payload preparation/rollback. Buffered operations need
  no TLS waiter, intrusive waiter membership, or generic rendezvous output
  parameters. Rendezvous retains its waiter lists and lazy TLS record.
- Put one mutex/condition pair in each Channel. Register a pointer to this
  embedded internal monitor record. Thread can lock and broadcast it directly,
  without a dependency on Channel's private representation or a callback.
- Remove the per-Thread Channel condition, its construction/destruction paths,
  and unmanaged blocking calls' temporary conditions. All users of a Channel
  wait on that Channel's condition using that Channel's mutex.
- Restore the original notification events: broadcast on buffered
  empty-to-nonempty and full-to-not-full transitions, rendezvous commitment,
  close, and a target Thread's stop publication. Remove targeted notification
  detachment/requeue and close-wakeup chaining.

This restores a measured baseline behavior instead of introducing another
wakeup policy. Broadcast may wake unrelated users of the same Channel; their
predicates and stop flags remain unchanged. A shared condition requires
broadcast, because one signal could wake the wrong waiter class. Independent
Channels retain separate mutexes and conditions.

### Preserve stop and lifetime ordering

The internal monitor declaration belongs with Thread's native wait bridge.
It contains exactly the existing mutex and the condition now owned by Channel.
The Thread slot still has idle, monitor pointer, and persistent STOP states.
The sentinel is a distinct never-used monitor identity. Registration and
unregistration retain their acquire-release CAS operations.

After successful fresh registration while continuously holding the Channel
mutex, a caller cannot already have a published stop. An earlier stop leaves
STOP and rejects registration. A later stop must claim the registered monitor
and acquire its mutex before publishing. Therefore the immediate path can omit
the separate caller-stop getter before commitment.

That proof ends at every mutex release, including condition wait and
stopped-peer prune/relock. After a gap, check stop before buffered mutation.
For rendezvous, check committed outcome first, then stop. A peer's stopped
state still needs checking before matching. Keep bounded stopped-peer pruning
and the tested commitment recheck after each prune gap.

Unregister after fixing the outcome. If stop claimed the registration, unlock
Channel and acknowledge through the completion mutex before returning. Failed
unregister is a lifetime signal only; it cannot cancel an already committed
operation. The matching caller never unregisters its peer.

Stop still takes completion then the registered monitor, publishes only its
target's stop flag, broadcasts that monitor's condition, releases the monitor,
and completes legacy completion notification. A repeated stop never dereferences
the sentinel. No Channel holder takes completion before releasing Channel.
The existing user/waiter-quiescence contract protects destruction of both
embedded native objects; the acknowledgement covers stop's borrowed pointer.

Owned transfer, rollback, destruction, Error dispatch, and native allocation
remain outside the queue mutex. Channel construction destroys an initialized
mutex if condition initialization fails. Thread-native startup failure cleanup
no longer owns a Channel condition.

### Costs still exposed for acceptance

Two registration CAS operations remain on each managed operation. Consolidated
entry and specialized buffering reduce surrounding work; they do not erase
the atomic cost. Baseline broadcasts restore possible wakeups that targeted
notification removed. No scheduler improvement is promised without measurement.

On this host, moving the condition saves 48 bytes per Thread and adds 48 bytes
per Channel relative to the current candidate. The registration word remains.
Relative to the original baseline, each Channel still has its new mutex and
each managed Thread still has registration state. Object-count-sensitive memory
measurements remain required. Neither expected storage nor wakeup costs are
preapproved tradeoffs.

## 3. Bound index memory with a flat table and a short lookup guard

Measured problem: retained old arrays nearly double index-requested bytes and
survive Pool release. A header inside each array adds allocator rounding.
Duplicate construction is already eliminated; do not replace its reservation.

The smallest safe correction is to restore a flat slot array plus scalar
capacity, using the existing index-publication mutex for lookup as well as
publication. Delete the per-table header, predecessor chain, and pointer-version
retry. Allocate the same slot-array shape as the original baseline.

### Lookup

`_find_block` locks the index, probes the current table, copies the matching
PoolBlock pointer, and unlocks. No slot-array pointer escapes. Only immutable
backing extent is inspected. Blocks remain allocated until quiescent shutdown,
so their pointers remain valid after the table lock is released.

Unlock before acquiring a Pool owner, performing promotion, freeing Scope
storage, dispatching Error, or running callbacks. Direct affected paths are
Pool free, promotion classification, and the initial classification in Pool own.
Existing-block allocation does not look up the index.

If the index is incomplete, read that monotonic state under the mutex, unlock,
and use the existing immutable registry fallback outside the mutex. Its atomic
head and immutable links remain; failure lookup stays linear as documented.
Do not hold a global lock over that fallback walk.

### Growth and reclamation

1. Reserve the single builder under the publication mutex. All new block
   registrations wait on the existing condition while that reservation is set.
2. Release the mutex. Allocate and copy from the stable old table. Readers
   continue using it under the mutex; registration writers cannot mutate it.
3. Acquire the mutex, which excludes every old-table reader. Publish the new
   pointer/capacity and the pending block, then unlock.
4. Free the old array outside the mutex. No reader can still own an old-table
   pointer, and future readers see the new table.
5. Only after free completes, reacquire the mutex, clear the reservation,
   notify waiting writers, and unlock.

Keeping the reservation through free prevents a preempted cleanup from
overlapping a second growth allocation. Existing-block allocations and current
index lookups continue during allocation, copying, and old-array destruction.
Only cold registrations wait for the whole reservation.

Allocation failure retains the current array, marks the index incomplete,
publishes the pending immutable registry link, and clears/notifies the
reservation. No old array is freed on failed replacement. No owner, depot,
or accounting lock is held on entry to registration. Stats retains its existing
owner -> index -> depot order; lookup never waits for an owner while holding
index, so it creates no reverse edge.

Structural memory bound: after completed growth, exactly one array remains.
If old capacity occupies S bytes and replacement occupies 2S, construction
temporarily requests 3S bytes, as at baseline. There is no inline header or
separate per-version allocation. Pool/Thread accounting and registration storage
are separate costs and remain in the memory acceptance scope.
This bounds requested index-array bytes, not allocator-usable storage, RSS, or
simultaneously prepared backing blocks. The current table still survives Pool
release, as at baseline; only historical versions are reclaimed after growth.

### Explicit contention tradeoff requiring Gary's decision

This reintroduces one shared lock/unlock per classification. Independent frees
can contend on it. Hash probing is expected short, not worst-case constant;
waiting to acquire the mutex is not bounded. The proposal does not preserve
the earlier promise of lock-free ordinary free/classification.

Unlike the original storage lock, this guard covers only the shared index
lookup. It never covers an owner-lock wait, payload operation, depot transfer,
allocation, copy, or array free. This directly applies the original request's
permission to narrow unavoidable shared-resource locking, but Gary must decide
whether this specific relaxation of the later design is acceptable.

It is proposed for review, not silently accepted. The measured independent-free
scaling improvements could shrink. The original baseline remains mandatory for
no-regression acceptance; also report comparison with the current candidate so
lost gains are visible. Passing baseline measurements does not itself approve
an architectural relaxation Gary has rejected.

Hazards/epochs or per-Pool reader registration add hot-path publication and
lifetime machinery. Locking every Pool needs an always-live registry and a
new lock-order proof. Sharded or segmented/radix indexes change representation,
lookup costs, and memory bounds. These are larger alternatives, not concealed
fallbacks if the short lookup guard fails.

## Independent review outcome

A fresh reviewer read this proposal, the profiles, current source, and contracts
without participating in its design or consulting the design workers. No code,
probe, build, or measurement was run during the review. The verdicts were:

- YES: technically coherent and safe as stated.
- YES: a credible targeted candidate for the measured costs, not proof of
  performance acceptance.
- NO on preserving the full earlier independent-contention goal. The shared
  classification mutex reintroduces contention between independent frees.

The reviewer found no new stop/commit race, lost-wake, or table-retirement flaw
in the stated ordering. The required disposition is to keep the index change
blocked until Gary explicitly accepts that architectural relaxation. The review
does not approve it or any performance regression.

The reviewer emphasized remaining costs: two Channel CAS operations, broadcast
wakeups, changed condition storage, a lookup lock even for large-allocation
classification, and an extra growth-only mutex pair to clear the reservation
after old-array free. The index-byte bound and surviving-current-table limitation
above now state the reviewer-requested distinction explicitly.

## Implementation order and acceptance after Gary's decision

The independent review is complete. A positive credibility verdict does not
establish no regressions or authorize the shared-lookup tradeoff. Gary has now
authorized only corrections 1 and 2. Index work remains blocked.

Authorized implementation sequence:

1. Restore the Pool allocation path and inspect optimized assembly, then rerun
   the single-worker release workload and both accounting modes.
2. Apply the connected Channel changes, preserve the controlled stop/commit and
   prune-gap probes, then rerun uncontended and shared workloads first.
3. Apply the index change only if its explicit contention tradeoff is approved.
   Check growth/failure/read overlap and memory through release/shutdown; measure
   independent frees, shared-Pool users, promotion, and concurrent growth.
4. Review and fix the authored diff before broader correctness/performance work
   and final publication validation. Run one compute job at a time and keep
   matched measurements exclusive.

Require matched original-baseline comparisons for every previously failing
case, plus the exposed costs above. Preserve exact revisions, commands, raw
samples, host conditions, CPU/instructions, elapsed time, and memory meanings.
No reproducible regression may merge to dev. Missing or inconclusive evidence
does not pass. Any measured tradeoff needs Gary's explicit approval; independent
scaling gains, correctness checks, or reviewer approval do not waive that rule.

## Implementation results

Sections 1 and 2 are implemented and independently reviewed. The combined
runtime passed 154 tests and 1,505 assertions in each accounting mode, plus
controlled refill/failure and Channel stop/commit probes. The Pool common-path
assembly count fell from 93 to 66 instructions; the original baseline was 72.

[Matched measurements](reference/independent-lock-fastpath-monitor-performance-2026-10-30.md)
cover 640 processes against the original baseline. The one-worker Pool-release
slowdown did not recur. Independent Pool and Channel gains remain. Shared
buffered Channel operations remain reproducibly slower, and smaller local
Channel overhead remains. Retained index memory is unchanged and still blocks
acceptance. Section 3 remains unimplemented and requires Gary's decision.

Nothing was pushed or merged. No tradeoff was accepted. Publication validation
was not run for this failing candidate; all changes remain local.

## Plan review

Reuse current ownership, block lifetime, ancestor-release rules, payload
transfer, stop publication ordering, and quiescent Channel destruction. Fresh
registration establishes the omitted immediate stop check; after every unlock
that fact must be re-established. No consumer reconstructs lifetime with a new
reference counter or validation walk.

The refill boundary removes measured inlining costs. Specialized buffering
removes generic dispatch and waiter machinery while reusing queue operations.
One Channel condition replaces Thread conditions and notification lists for
buffering. The flat index deletes versions and uses its existing mutex for the
small interval in which a table pointer is borrowed. This last change narrows
the implementation but weakens the lock-free lookup objective explicitly.

No new public validator or diagnostic is proposed. Focused negative/race probes
cover existing allocation/native-init failure cleanup, lost wakes, stopped-peer
commitment, unregister lifetime, and old-table access during publication. They
protect wrong outcomes and use-after-free, not a new caller obligation. No new
recurring gate or benchmark framework is proposed.
