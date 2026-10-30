# Revised Pool accounting, index construction, and Channel handoffs

> Status: blocked - implemented locally; revised candidate fails performance acceptance.
> Requested 2026-10-30 after the local candidate failed performance acceptance.
> Source reviewed at `d4a0ccbcc9fb41400992e7cb6dd9f0771d83b62d`.
> Implemented and measured at `a6be0e6c49a995aed7d097a526235b2ef12e4c54`.
> Performance measurements and no reproducible regressions remain mandatory
> before merging to dev. Every measured tradeoff requires Gary's explicit approval.
> An independent reviewer answered yes to credibility, without claiming acceptance.
> Gary authorized implementation and measurement of previously failing workloads first.
> [Results](reference/independent-lock-redesign-performance-2026-10-30.md):
> Pool accounting regressions removed; Channel, single-worker Pool release,
> and retained index memory regressions remain. Nothing pushed or merged to dev.

This revises three mechanisms in the
[implementation plan](independent-pool-and-channel-locks.md). Its unaffected
ownership, depot, compatibility, validation, and delivery requirements remain.
The [measurement report](reference/independent-lock-performance-2026-10-30.md)
records the failed candidate and retained raw evidence.

## What the revision removes

| Path | Failed candidate | Revised proposal | Remaining cost |
| --- | --- | --- | --- |
| Accounted Pool allocation/free | Every Pool modifies the same atomic counter words; requested bytes uses retrying CAS | Update private Pool counters under the existing owner lock | Extra counter storage; aggregation during stats |
| Index growth | Multiple writers allocate and copy the same replacement; losers discard and retry | Reserve exactly one builder; pause new block registration during its copy | Cold registration waits; published old tables remain |
| Managed immediate Channel operation | Queue mutex plus participant mutex | Queue mutex plus registration/unregistration CAS in the caller's Thread | Two atomic operations per operation |
| Rendezvous commitment | Queue mutex plus both participant mutexes | One queue mutex orders both participants' commitments | Necessary shared-Channel serialization |
| Channel sleep/wake | Transfer from queue mutex to participant mutex and back | Wait on the participant's condition using the queue mutex directly | Native condition scheduling |

These are structural cost reductions, not a claim of measured success. The
previous candidate took 51.924 ms against 35.881 ms for one million managed
Channel round trips. Eight independent accounted Pools took 3550.522 ms
against 1736.810 ms for 16 million allocation/free pairs. Removing identified
costs does not prove that the replacement meets either baseline.

## Pool accounting: use the existing owner serialization

Keep `struct Pool`, `PoolStats`, and public signatures unchanged. When accounting
is enabled at startup, extend the constructor's existing control allocation
with a private trailing record: four counters and two intrusive registry links.
The proposed record is 48 bytes on this host, before any allocator rounding.
Do not allocate this trailer when accounting is disabled.

The sole constructor in `lib/pool/interning.x` owns initialization and lifetime.
Register the fully initialized trailer before returning the Pool. Constructor
failure must leave no registered record. Root Pools use the same constructor.
No caller constructs a second accounting owner or registers a native thread.

Update allocation calls, requested bytes, free calls, and slot reuse while
holding the Pool owner lock already required for that operation. Small
allocation accounting moves before owner unlock. Large request accounting moves
inside the existing owner lock, retaining its present position before native
allocation. Preserve existing success/failure counting points on every path.
Free accounting uses the same owner selected by the existing free operation.
Promotion does not transfer or replay historical traffic counts.

Use relaxed atomic loads and stores for the counters, because stats can read
concurrently. Owner serialization makes read-modify-write instructions and CAS
loops unnecessary. Requested bytes saturates locally. Other counters retain
their existing unsigned arithmetic. The existing no-worker lock bypass remains.
This does not extend support to native callers that bypass existing Pool
thread-initialization requirements.

One private registry mutex protects live trailer membership and cumulative
retired totals. It is absent from allocation/free hot paths:

1. Stats holds this mutex while summing live counters and retired totals.
2. Release holds the dying Pool's owner lock, takes the registry mutex, folds
   its counters into retired totals, and unlinks its record in constant time.
3. Release unlocks the registry before destroying the Pool's Scope.

Thus stats cannot count a record both live and retired, or read freed storage.
Totals survive Pool destruction. Saturating the sum of locally saturated
requested-byte counts preserves global saturation. Quiescent totals remain
exact; a concurrent snapshot is not a transaction across independent operations.

Stats must not acquire any Pool, index, or depot lock while holding the
accounting registry mutex. Read structural metrics in their existing bounded
sections, then release those shared locks before scanning accounting records.
This avoids holding the depot or index mutex for an O(live Pools) traversal.
No accounting registry holder waits for an owner lock.

This eliminates intentional shared counter writes between independent Pools.
It does not promise cache-line separation between arbitrary native allocations.
Stats becomes O(live Pools), and a stats scan can delay Pool creation/retirement.
Measure frequent stats calls, Pool churn, and many simultaneously live Pools.
The trailer's memory cost is not preapproved by this design.

Rejected alternatives: padding the current counters leaves true sharing;
fixed shards retain collisions; permanent native-thread records retain storage
with thread churn. Reclaiming thread records would introduce unrelated native
thread cleanup machinery. No Scope accounting redesign is included.

## Index construction: one builder, no speculative copies

Keep the immutable extent lookup and retained published index versions. Add a
builder reservation and condition to the existing index publication owner.
Every new block registration checks the reservation under the publication mutex.
While reserved, registration writers wait on the condition, releasing that mutex.

The writer that needs growth reserves construction and captures the current
table. It releases the publication mutex before allocating or copying. The
reservation freezes all index/registry insertion, so its source stays unchanged.
Existing allocations, frees, index readers, depot transfers, and stats do not
wait for the builder reservation.

After construction, the builder takes the publication mutex, publishes the
replacement and its pending block, clears the reservation, and wakes waiting
writers. Pending block publication includes at most two page entries, immutable
registry linkage, and structural counter updates. No owner, depot, or accounting
mutex may be held while entering registration or waiting for the builder.

On allocation failure or capacity exhaustion, preserve the existing incomplete
index flag and immutable registry fallback. Publish the pending block through
that fallback, clear the reservation, and wake writers. They recheck the state
before registering. No allocation failure leaves a reservation held.

Delete version validation, discarded-candidate retries, and concurrent rebuild
machinery. There is at most one unpublished replacement, and one copy per
successful growth. No native mutex covers allocation or rehashing. Logical
serialization remains for new backing-block registration because writers share
one index. A paused builder can delay those cold writers; it cannot block an
existing-slot allocation or free in another Pool.

Hash insertion is expected short, not worst-case constant. Retired tables
still consume storage until shutdown. A doubling index retains less than one
current table's slot capacity in older arrays, plus headers; growth temporarily
adds one replacement. This bounds duplicate construction, not overall RSS.

The prior growth run measured 113,541,120 versus 84,721,664 bytes peak RSS.
It did not isolate index memory or equalize simultaneously live allocations.
Repeat it and add an equal-live-allocation barrier plus temporary index-byte
accounting. Measure current, retired, and unpublished table bytes separately
from backing blocks and process RSS. If retention itself causes a reproducible
regression, this design still fails. Do not silently substitute a segmented or
radix index with different lookup costs.

## Channel: one mutex for queue, commitment, and condition waiting

Keep each Channel's queue mutex and targeted waiter lists. Retain each managed
Thread's condition, but remove its Channel participant mutex. A waiter uses
`pthread_cond_wait` with the Channel queue mutex. Signals occur under that same
mutex. Do not replace targeted notification with a shared condition broadcast.

Add one atomic active-Channel registration word to each managed Thread. Its
states are idle, the address of a Channel's mutex, and a persistent stopped
sentinel. Use a private `pthread_mutex_t *` representation with a distinct,
never-locked sentinel object. Thread can lock the registered mutex directly;
it needs no dependency on Channel's representation or new Channel callback.
This is not a public handle or additional allocation per operation. References
to registering or capturing a Channel below mean this mutex address.
Initialize the slot before Thread start. Register once per synchronous operation
and retain that registration across waits. Use acquire-release CAS/exchange
for registration, unregister, and stop claiming; acquire failure loads observe
the sentinel. Never reset the sentinel. This also prevents concurrent binding
of one Thread condition to different Channel mutexes.

### Ordinary operation

1. Prepare payload/storage outside the queue mutex, as today.
2. Lock the Channel and CAS the caller's registration from idle to this Channel.
   A stopped sentinel prevents the operation from committing.
3. Check stop and queue predicates, then commit or enqueue and wait. Queue
   rewiring and commitment use only this mutex. Wakeups recheck predicates.
4. Once the result is fixed, unlink and CAS registration from Channel to idle.
5. Unlock before payload adoption, rollback, destruction, or Error dispatch.

The matching caller must never unregister a queued rendezvous peer. That peer
owns its registration until its own operation finishes. Check committed outcome
before a later stop on wake, preserving success for an already committed pair.

### Stop and lifetime handshake

`Thread.stop` takes the existing completion mutex and atomically replaces the
target registration with the persistent stopped sentinel.

- If it captures idle, it publishes stop under the completion mutex. Future
  Channel registration fails, and legacy completion waits retain their ordering.
- If it captures a Channel, it takes that Channel's mutex before publishing
  `stop_requested` and signaling the target Thread's condition.
- It releases the Channel before completing legacy completion notification and
  releasing the completion mutex. Repeated stops remain serialized there.
- A repeated stop that captures the sentinel never dereferences or locks it.
  Completion-mutex serialization ensures the first stop has published the flag.

If an operation's unregister loses to stop, the operation releases the Channel
mutex and then acquires/releases the completion mutex before returning. This
rare acknowledgement waits until stop has finished using the borrowed Channel.
There is no global mutex acquisition on the ordinary successful path.

| Race | Ordering and result |
| --- | --- |
| Stop wins before registration | Registration sees the sentinel and cannot commit |
| Operation registers first | Stop must acquire its Channel mutex to publish the stop flag |
| Stop races final check and commitment | Stop publication cannot occur between them; both use the same mutex |
| Operation unregisters first | Its result is fixed; stop captures no Channel pointer |
| Stop claims registration first | Operation acknowledges after unlocking, before returning |
| Stop races a queued rendezvous peer | Both participants register the same Channel; one mutex orders stop and pair commitment |
| Stop races condition sleep | Final predicate check, signal, and atomic wait/unlock share the Channel mutex; no lost wake |

The sentinel claim reserves the registration. For an already registered
operation, stop publication under the queue mutex is the ordering point.
A concurrent commitment can win before that publication, as with the previous
monitor protocol. A registration rejected by the sentinel overlaps a stop
already in progress and may cancel immediately.

Lock order is completion then Channel in stop. An operation acknowledges only
after releasing Channel. No queue path acquires completion while holding Channel.
No user callback, allocation, or payload finalizer runs under either lock.
Stop may wait for a short queue section; a stalled queue owner can delay it and
other completion operations. Measure stop/completion interference explicitly.

The acknowledgement preserves the existing contract that every Channel user
finishes before destruction. Stop cannot retain a Channel pointer after the
registered operation returns. Thread condition lifetime still ends after join.
No Channel refcount, retired Channel list, hazard registry, or caller obligation
is added.

Unmanaged or cleanup-masked callers need no registration. An unmanaged blocking
call initializes only a stack condition outside the queue lock, rechecks after
locking, and destroys it after unlinking and unlocking. Keep temporary pointer
cleanup confined to that helper. Managed and immediate unmanaged paths need no
new mandatory cleanup registration. Preserve owned-send rollback separately.

On this Mac, the proposal replaces 112 bytes of Thread mutex/condition storage
with a 48-byte condition and an 8-byte registration word: 56 fewer bytes than
the failed candidate, but still additional storage against the original baseline.
No Channel condition is added. Ordinary managed operations still pay two CAS
operations. Shared-Channel wake scheduling and close notification remain costs
to measure, not assumed improvements.

## Implementation and acceptance after design review

Implement the reviewed and authorized revision through the
three bounded replacements, preserving the original contracts and targeted
correctness tests. Remove the displaced mechanisms rather than layering both.
Use controlled race probes for stop/registration/unregister, peer commitment,
sleep entry, and quiescent destruction. Check counter retirement/saturation,
constructor rollback, and index-allocation fallback. These protect totals,
lost wakes, operation outcomes, and storage lifetime; they add no public checks.

Before broad validation, rerun each reproduced blocker with matched baseline
and candidate binaries. Include both accounting modes, single-worker and
shared-object cases, independent scaling, growth/release/churn, frequent stats,
stop/close storms, idle Thread/Channel footprint, and unmanaged waits. Retain
elapsed time, CPU time, memory, exact revisions, commands, and raw samples.
Diagnostic instrumentation runs separately from acceptance timings.

Run one owned compute job at a time. Quiet matched runs exclude all owned
builds, tests, and profilers. Do not use a faster independent workload to excuse
a regression on a shared or single-worker workload. Reproducible regressions
block merging; missing or inconclusive evidence does not pass. Any tradeoff,
including stats cost, stop latency, or memory, requires Gary's explicit approval.

After focused acceptance, complete the existing compiler performance checkpoint,
review and fix the authored diff, integrate current dev, and perform the existing
publication validation on the final tree. Remeasure any relevant integrated
changes. Nothing in this proposal authorizes accepting the failed candidate.

## Implementation result: 2026-10-30

All three replacements were implemented. A follow-up confines Channel TLS waiter
setup to operations that must block. The final combined focused checks passed
153 tests and 1473 assertions in each accounting mode. Controlled probes passed
for counter totals, index builder/fallback behavior, stop/commit, condition wait,
borrowed-monitor lifetime, and commitment during stopped-peer pruning.

The required failing-workload-first measurements still reject this candidate:
the final Channel penalties are about 20-26%, the single-worker Pool-release
penalty is 4.4%, and equal-live diagnostics confirm retained index memory growth.
The private Pool counters produce substantial improvements in the formerly
regressing accounting workloads. These gains do not waive the remaining failures.
See the linked result record for absolute measurements, raw evidence, and limits.

No further architecture change or tradeoff is authorized by these results.
The candidate stays local. Publication validation, the compiler performance
checkpoint, and remaining broad measurements were not run for a candidate that
already fails the mandatory acceptance rule.

## Plan review

Existing boundaries establish live Pool ancestor ownership, release order,
immutable backing extents, joined Thread lifetime, and quiescent Channel
destruction. The proposal relies on these facts without adding validators or
caller obligations. The stop acknowledgement is necessary to extend an active
operation's lifetime across a concrete stop-reader race.

The accounting trailer replaces shared hot counters; its registry exists only
to preserve process totals across Pool retirement. The builder reservation
replaces speculative copies and version retries. Channel registration replaces
participant mutexes and cross-mutex sleeping, while reusing targeted conditions,
queue lists, and the completion mutex. Each representation has one owner and
a bounded responsibility; no generic synchronization framework is proposed.

No new public diagnostic or defensive validator is proposed. Focused probes
exercise counter preservation, failure cleanup, lost wakes, stop/commit order,
and borrowed-pointer lifetime. The source and race analysis establish which
costs disappear. Only subsequent matched measurements can establish no regression.
