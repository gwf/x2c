# Detached Channel payload ownership

> Status: active
> Authorized on 2026-10-22 to correct the implementation shipped at 38f2d503e.
> Coordinator owns combined review, performance comparison, gate, and dev delivery.

## Contract

Remove the global Scope link mutex, without adding a replacement mutex or
changing ordinary private allocation behavior. Allocation lists and ownership
trees require exclusive caller access. Shared-parent concurrent adoption is
superseded by detached Channel handoff.

`Scope.transfer(NULL)` detaches a storage subtree. Its allocations still belong
to that scope; `Scope.owner(object)` recovers it through allocation headers.
Transfer to a live private scope reattaches it. No new owner pointer is added.

Ordinary `Channel.send` stays nonowning. Explicit `Channel.send_owned` accepts a
live Scope-allocated payload with its own inactive, exclusively owned storage
subtree. It detaches before publication and restores the original parent on
failed send before dispatching the error. Acceptance relinquishes sender access
and cleanup obligations. Aliases and explicit sender cleanup are caller concerns.

Messages and rendezvous waits carry an owned bit, not another scope pointer.
Receive recovers the scope from the payload and attaches it to the receiver's
private active scope before returning or dispatching errors. Prepare that owner
before any commit. A committed rendezvous completes adoption despite later stop.
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
