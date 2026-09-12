# Recommended research plans

> Status: reference - proposed plan structure, 2026-09-11.
> Gary requested investigation and recommendations, not implementation of
> these deferred items. Each proposed filename below is a future scoped plan,
> not an approved implementation or a newly required process.

The [closeout](archive/closeout-outstanding.md) delivered its implementation.
The [onboarding experiment](archive/agent-onboarding-accuracy.md) is retired
with failed acceptance: Fable's final scores were 10/15, 8/15, and 10/15.
Gary stopped further improvement attempts. The [two deferred questions](archive/ISSUES.md)
and four remaining research opportunities are preserved below. Aggregate
initializer growth was already repaired and is not part of this agenda.

Recommend five independently deliverable plans. Start with memory attribution;
use its findings to decide whether ownership changes or pool trimming are
worth pursuing. Build performance and editor reuse can be investigated
independently. Scope application distribution when there is a target consumer.
This review inspected current source and retained reports; it did not rerun
memory/performance benchmarks or establish a speedup or new runtime defect.

## 1. memory-retention.md

Combine the unresolved Torch process footprint with the known Pool depot
retention as two separately measured questions. Do not assume one explains
or fixes the other.

Evidence: [Torch's report](../packages/torch/benchmarks/REPORT.md) records stable
native/Scope counts and bounded canonical storage in the pooled variant,
but an unexplained incremental process-peak excess. Historical pool churn is
not equivalent to a leak. [Pool._block_return](../lib/pool.x) places released
blocks in the process depot; the registry frees them at shutdown. The block
registry/page index assumes storage remains allocated until shutdown.

First reproduce request loops and burst/release/reuse on current source.
Separate live handles, Scope allocations, canonical active/depot bytes,
process footprint, and native-library/allocator retention. Sample after
warmup and after each lifetime boundary. Reuse the existing Torch profiles,
counters, and Pool statistics. Record fresh-process repetitions and platform
identity; keep historical figures labeled historical.

Only if depot retention is material, compare bounded idle retention or
explicit trimming against current reuse. A trim must remove registry/index
entries under the existing storage lock; freeing depot pointers alone is
unsafe. Preserve canonical identity, promotion, interior-pointer lookup,
thread safety, and live objects. Measure repeat-burst allocation/latency costs.
The first deliverable is attribution and a repair/no-change decision. A memory
policy or public trim API requires a separately settled design.

## 2. temporary-result-ownership.md

Treat the guard as a correctness boundary to preserve, not an obsolete check.
[Compiler.discard_helper](../src/protocol.x) retains temporary inputs when an
ordinary pointer/aggregate-returning function might return an input or an
interior view. [Expression lowering](../src/expressions.x) records fresh
callees for protocol operators, numeric converters, and their wrappers.
Current operator cleanup fixtures cover borrowed handles and interior views.

Inventory actual missed early-release opportunities, beginning with Torch
chains. Distinguish an unnamed fresh intermediate from a named variable's
replaced value: broadening the guard does not by itself manage assignment
lifetimes. Reuse existing fresh-callee facts and discard lowering. Do not add
an independent lifetime system or infer freshness from return type alone.

Compare existing explicit free/scope patterns with narrowly provable freshness.
If ordinary-call annotations or inferred return contracts are justified,
settle their public meaning and compatibility first. Require unchanged
borrowed-result behavior plus a measured useful reduction in live temporaries.
Retain tests for fresh chains, returned inputs, interior views, and wrappers.
A no-change conclusion is valid if the benefit does not justify a new contract.

## 3. native-build-reuse.md

[Build._compile_fingerprint](../src/build.x) synchronously preprocesses each
source before its compile action enters the bounded job loop. Unchanged
retained builds therefore serialize fingerprint work even with multiple jobs.
This establishes the scheduling opportunity, not its performance value.

Measure unchanged and small-edit builds at jobs 1 and N. Prototype overlap
within the existing ToolAction/CcJob scheduling owner, then compile only cache
misses. Preserve preprocessed-input fingerprints, include search and shadowing,
flags, failure propagation, and state publication after successful completion.
Reuse retained native-build probes. Do not weaken correctness to timestamp
checks or add a second scheduler. Ship only if repeat measurements justify the
complexity and unchanged builds still skip compilation correctly.

## 4. editor-semantic-reuse.md

[SemanticService.analyze](../etc/vsc-extension/semantic.js) launches a worker
for each query; [editor_request](../src/editor.x) opens a new frontend each
time. Prefer one response containing existing compiler-owned semantic facts,
with hover/definition lookup in the adapter, over a persistent compiler daemon.

First measure repeated diagnostics/hover/definition on unchanged inputs and
identify the exact fact set needed. Settle invalidation before caching:
open-document revision alone misses disk imports, native preprocessing inputs,
compiler/configuration changes, and macro evaluation effects. Preserve current
cancellation and stale-response suppression. Do not silently promise freshness
that a dependency/environment key cannot establish.

Acceptance should compare results against current one-request analysis and
prove reuse for stable inputs plus invalidation at each supported change.
Measure latency and retained memory. If a complete reusable snapshot cannot
be bounded simply, retain the current behavior and record the limitation.

## 5. torch-application-distribution.md

Torch currently embeds its prepared-prefix rpath. The existing
[package bundle owner](../packages/tools/bundle.py) packages interfaces,
archives and declared native inputs; the [documented contract](../docs/src/guide/packages.md)
explicitly excludes shared-library relocation. Moving a runnable Torch app is
new scope, not a missing promise of completed package integration.

Recommend an executable directory with private runtime dependencies, using
existing bundle/dependency metadata where applicable. First settle supported
platforms/architectures and whether a runnable application or reusable consumer
package is desired; the deferred item names applications. Determine dependency
closure, platform-relative loader paths, required licenses, and remaining
system frameworks/libraries. Preserve platform/compiler ABI limitations.

Proof should move the directory, hide the original prepared prefix, and run a
CPU/checkpoint example on supported macOS and Linux environments. Inspect
native dependencies; test MPS separately where supported. Do not present an
emulated Linux timing as native performance. Packaging/signing/distribution
policy must be scoped before implementation, with no toolchain installation
or release-system expansion assumed here.

## Retirement and plan review

The old umbrella and two-question list are archived, rather than maintained
as duplicate active checklists. Their outcomes and raw evidence references
remain intact. The stalled onboarding effort has no successor plan. Create
only the individual plans selected for further work; this reference is the
recommended grouping, not five implementation commitments.

These scopes reuse compiler facts, native scheduling, existing benchmark
profiles, Pool storage ownership, and package metadata. They do not add
consumer validation of already established facts. Freshness/invalidation and
loader closure are unresolved contracts, not excuses to introduce parallel
owners. No implementation, new validator, negative fixture, recurring gate,
or mandatory process is added by this recommendation. Any selected plan must
review its resulting authored diff and use the existing publication checks.
