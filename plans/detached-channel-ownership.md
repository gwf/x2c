# Detached Channel payload ownership

> Status: active - delivery evidence closeout, 2026-10-24.
> The correction is present in `dev` at `7e9fd0178`. Final benchmark
> comparison and the resolution of the historical publication hold were
> not located in the reviewed repository records.

## Current disposition

Detached Scope transfer and owned Channel handoff are present, including
`fc6ea2d51` and `27ddb7464`. Receiver transport cleanup landed in
`43bf899a7`; constant-time Map replacement landed in `cee694038`. Current
Array and Map code creates contents scopes lazily. These commits are
ancestors of the inspected `dev` tip; the implementation is not merely a
local candidate waiting to be written.

Keep this plan open to recover and link the final baseline comparison,
combined verification, and delivery/hold decision. The old focused-test
counts below are dated evidence, not a current run. This review does not
infer recovered performance or renewed publication authorization from
the code's presence. It does not reopen the ownership design or dispatch
new implementation. Ordinary later work follows current root guidance.

## Earlier checkpoint

> Historical status: active
> Authorized on 2026-10-22 to correct the implementation shipped at 38f2d503e.
> Coordinator owns combined review, performance comparison, and verification.
> Publication held by Gary: show benchmark results before publishing.
> The first local correction passed correctness checks but retained collection costs.

## Contract

Remove the global Scope link mutex, without adding a replacement mutex or
changing ordinary private allocation behavior. Allocation lists and ownership
trees require exclusive caller access. Shared-parent concurrent adoption is
superseded by detached Channel handoff.

`Scope.transfer(NULL)` detaches a storage subtree. Its allocations still belong
to that scope; `Scope.owner(object)` recovers it through allocation headers.
Transfer to a live private scope reattaches it. No new owner pointer is added.

Ordinary `Channel.send` stays nonowning. Explicit `Channel.send_owned` prepares
an exclusive detached transport scope for an ordinary Map or Array. For typed
or custom payloads, the caller prepares that subtree with the concrete type's
`move_to` operation. Failed sends restore the original container owner or
prepared subtree parent before dispatching errors. Acceptance relinquishes
sender access and cleanup obligations. Aliases and armed sender cleanup remain
caller responsibilities.

## Lazy container ownership correction

Gary authorized this design on 2026-10-22 after the first correction left
collection instruction counts 35% above the original baseline. Array and Map
records and buffers use ordinary allocation ownership. Their existing scope
field starts null and owns only explicitly acquired contents. Requesting the
contents scope creates it lazily beneath the record's allocation owner.
Insertion remains borrowed and creates no scope.

Map growth stages replacement buffers before commitment. The authorized
constant-time correction splices each new allocation immediately before its
old allocation using Scope's existing detach/relink helpers. Normal cleanup
then removes the old allocations. No owner lookup, field, lock, or change to
ordinary allocation/free is required. Test neighboring links, cross-scope moves,
finalizers, and growth while a temporary allocation scope is active. Compare
growth after zero and 100,000 intervening allocations against the original
baseline, alongside the existing Scope and construction workloads.

Cleanup destroys the contents scope, if any, then frees internal buffers and
the record. Explicit `move_to` moves the record, every backing allocation, and
the existing contents scope together. Growth places replacements under the
record's owner. Context export preserves explicit nesting without treating the
contents scope as the record's owner.

Owned Channel sends prepare detached transport storage only when requested.
Collection storage moves together into that scope; failed sends restore the
original owner. Queued cleanup still recovers the transport scope from the
record's existing allocation header. No private allocation locks, new owner
pointers, descriptor machinery, or changes to canonical-value ownership.

Messages and rendezvous waits carry an owned bit, not another scope pointer.
Receive recovers the scope from the payload. Ordinary containers move into the
receiver's private active scope and the empty transport scope is destroyed.
Prepared custom subtrees attach beneath that owner. Prepare the owner before
any commit. A committed rendezvous completes adoption despite later stop.
Channel teardown after all users finish destroys scopes still queued, outside
the existing queue monitor. Normal close continues to permit draining.

Queue nodes use native allocation and explicit sender/queue/receiver cleanup,
avoiding concurrent allocation-list mutation in the Channel's storage scope.
No allocation, Error dispatch, or payload destruction occurs inside the monitor.
Canonical values and borrowed messages retain their existing lifetime rules.

## Implementation and verification

Storage worker owns Scope sources, storage tests, and the ownership guide.
Channel worker owns transport, Channel tests, and the Channel guide. Coordinator
owns word-count adoption, cross-component tests, shared metadata, and delivery.
Workers provide private commits and do not publish independently.

Check detached subtree lifetime, header lookup after detach, failed-send rollback,
buffered and rendezvous adoption, abandoned owned-message cleanup exactly once,
receiver failure cleanup, and unchanged borrowed transport. Run the word-count
and service examples and the existing combined publication gate.

Compare the original b4c2b428 baseline, shipped 38f2d503 regression, and corrected
candidate using the same Scope and collection workloads. Preserve absolute
instruction counts and per-operation timings. Do not claim all collection
overhead is recovered merely because the allocator lock is removed. Further
architectural changes require discussion, not speculative performance fixes.

## Design review

The shared queue already serializes ownership acceptance and delivery. Detaching
and attaching touch private trees only, removing the reason for shared Scope
metadata. Existing allocation headers identify the cleanup scope. The only
message metadata added distinguishes explicit owned sends from unchanged borrowed
sends. This replaces shared-parent lifetime adoption rather than layering another
ownership protocol over it. Finalizers and failure cleanup remain outside locks.

Combined focused checks pass 84 tests and 778 assertions. Independent source
review found no lifecycle defect in private Scope detach/reattach or owned
Channel commitment. Tests cover stopped rendezvous rollback, but do not force
every postcommit scheduling interleaving. Native allocation failure is not
fault-injected. Final gate and repeated baseline comparisons remain required.
