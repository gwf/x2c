# Recommended research plans

> Status: reference - independent work pursued on 2026-09-11.
> Gary authorized proceeding in parallel where little further input was needed.
> Delivery commit subject: `overlap native fingerprints and close research probes`.

## Current outcomes

All five topics received bounded investigation. One justified an implementation:

- [Native build reuse](archive/native-build-reuse.md): preprocess fingerprints
  now use the existing bounded job scheduler. A synthetic 16-file warm build
  fell from 0.456 to 0.167 seconds at four jobs; single-job time was unchanged.
- [Memory retention](archive/memory-retention.md): fresh Torch probes identify
  substantial allocator-reclaimable residency, with only 2 KB in its Pool
  depot. A separate burst proves intentional depot retention and full reuse.
  No Pool policy or ownership change is justified by these measurements.
- [Temporary ownership](archive/temporary-result-ownership.md): the existing
  fixture reproduces why returned inputs/views must survive. Preserve the
  guard and explicit named-value lifetimes; no new freshness contract.
- [Editor reuse](archive/editor-semantic-reuse.md): existing callers already
  debounce diagnostics. No observed repeated-request workload justified more
  cancellation state, and arbitrary macro inputs prevent revision-only caching.
- [Torch relocation](archive/torch-application-distribution.md): a moved macOS
  application with four private libraries passes CPU/checkpoint execution and
  matches the original's 19 records and 64 curve observations. Public packaging
  remains future scope; this probe adds no signing/platform promise.

Raw evidence is retained in
`/Users/gary/Documents/x2c-evidence/research-20260912/`. Performance experiments
were run in coordinated quiet windows, not concurrently with agent builds.
These outcomes supersede the initial uncertainty below without rewriting its
historical scope. No deferred language or memory-policy change was inferred
from the implementation authorization.

The earlier [closeout](archive/closeout-outstanding.md) implementation remains
complete. The [Fable effort](archive/agent-onboarding-accuracy.md) remains
intentionally retired with failed acceptance and was not reopened.

## Original research scopes

The following records the initial five recommended boundaries. Further work
should start from the completed outcome linked above, not repeat this scouting.

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
remain intact. The stalled onboarding effort has no successor plan. The five completed investigations now have archival records above. Further
implementation needs the evidence and scope identified by each outcome; there
is no duplicate active checklist.

These scopes reuse compiler facts, native scheduling, existing benchmark
profiles, Pool storage ownership, and package metadata. They do not add
consumer validation of already established facts. Freshness/invalidation and
loader closure are unresolved contracts, not excuses to introduce parallel
owners. The original recommendation added no implementation or process. The authorized
follow-up changes only the existing native scheduler and extends an existing
probe case; no recurring gate or new process is added. Any selected plan must
review its resulting authored diff and use the existing publication checks.
