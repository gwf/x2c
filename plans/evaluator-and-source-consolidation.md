# Evaluator and source consolidation campaign

> Status: active
> Planned 2026-09-26; execution has not started. Gary requested an
> orchestrated campaign covering the evaluator and all named cleanup
> candidates, initially limited to the evaluator, strongest small cleanups,
> and bounded prototypes. Later compatibility and distribution decisions
> remain queued. The root session owns orchestration and integration.

## Result and scope

Make deep hand-written Lisp recursion work and simplify existing compiler
and runtime owners where a concrete implementation proves worthwhile.
Pursue every candidate to a recorded disposition; pursuing an item does not
mean landing its original proposed design despite contrary evidence.

The initial implementation scope is E1 and R1-R3 below. Initial experimental
scope is E2 and P1-P5. Workers may build prototype patches and measurements;
prototypes are not automatically production changes. Later rows stay queued
until this first wave has results. Preserve existing public behavior except
for the expressly intended evaluator improvement. No AUTO removal, native
meta redesign, general value-transfer framework, release promotion, or new
recurring gate belongs to the first wave.

The campaign uses the existing task skills and publication workflow. It adds
no build/precommit requirement, recurring benchmark, or mandatory report
outside this campaign. Focused experiments answer specific design questions.

## Evidence and starting point

Baseline: fetched origin/dev equals e3d5eb14 on 2026-09-26. Recheck source
and remote state when each task starts. The proposal table is on
spike/evaluator in plans/native-meta-execution.md:238-266; it labels its line
counts "Overestimates". Do not carry those estimates forward as savings.

Evaluator commit 658fb92d changes only lib/lisp.x. Its parent version matches
this baseline. An isolated replacement-object experiment established:

| Observation | dev | evaluator candidate |
| --- | --- | --- |
| 10,000 mutual tail calls with AUTO disabled | call-stack | true |
| Same call with AUTO enabled and rest parameters | call-stack | true |
| 1,500 non-tail calls with AUTO disabled | call-stack | 1500 |
| Exhaust a 100-call budget, then start a fresh evaluation | rejects, recovers | rejects, recovers |
| lisp_suite and lisp_auto_suite | 101 passed, 1,197 assertions | same |

This proves relevance, not timing invariance or stack-bound portability.
Current dev still has AUTO. Array/Map already instantiate shared core-family
macros: lib/array.x:53 and lib/map.x:94; that row is already complete.
The original research logs and report are workspace evidence under debug/
and .context/dev-cleanup-research-2026-09-26.md; the decisions needed to
resume the campaign are recorded here.

## Ownership and parallel execution

The root is the sole integrator. Use up to three isolated workers alongside
it. Each worker creates its own worktree through the managed worktree tool,
fetches origin, branches from the dispatched baseline, and records that exact
base. Branches use codex/. Workers never edit the integration checkout,
merge dev, commit, push, run a publication gate, or run tools/land-dev.

| Initial worker | Work | Exclusive authored files |
| --- | --- | --- |
| Evaluator | E1, then E2 experiment | lib/lisp.x, unittest/test-lisp.x, unittest/test-lisp-auto.x, relevant authored Lisp documentation |
| Runtime | R1, then R2; R3 may follow while other lanes run | lib/error.x, lib/error-private.xmacro, lib/mutex.x or its narrow internal companion, lib/logger.x, lib/dispatch.x, lib/context.x; corresponding existing tests/comments |
| Compiler | P1, then P2 and P3 in order | src/compiler.x, src/parse.x, src/transform.x, src/lambda.x, src/cleanup.x, src/emit.x, src/cache.x; focused existing fixtures |

When a slot frees, start P5 MatchCache on lib/match.x and its existing tests
and benchmark. P4 transaction measurements may run against an unchanged
baseline independently; its implementation shares compiler.x and must wait
for that file owner. Worker ownership includes any discovered caller edits:
report an overlap before extending the patch. Keep the two compiler AST
experiments sequential. Do not let fixtures shared by two workers acquire
competing expected-output updates.

If another session owns a shared file, coordinate its boundary before
editing. Use chat messaging only within Gary's authorized coordination;
do not interrupt unrelated work or change its branches.

Every dispatch includes the task ID, result, base, allowed files, existing
example, strongest compatibility boundary, focused checks, and finite
endpoint. Each worker first runs make build-safe in its own worktree and
uses make build after source changes. It returns an authored patch against
its recorded base, a concise result, focused check commands/results, and
remaining uncertainty. Save patches in the session scratchpad, never in
unittest/build/. Generated bootstrap and docs belong to integration.

Benchmark quiet windows are serialized on the host. Parallel source work is
useful; parallel builds during a timing experiment are not valid evidence.

## Initial implementation tasks

### E1. Evaluator tail calls

Owner: lib/lisp.x and existing Lisp tests. Start from the relevant portions
of 658fb92d, not the later spike branch. Keep AUTO, call-step budgets,
source-function automatic-storage ownership, and speculative expansion
accounting intact. Implement tail-position evaluation for hand-written Lisp
without nesting a C activation for each mutual call.

First retain the existing non-tail depth fence while proving the tail-call
change. E2 separately decides whether the stack-usage fence replaces it.
Do not condition tail calls on approving that unrelated depth relaxation.
Preserve left-to-right argument evaluation, macro expansion semantics,
closures and returned value lifetimes, error unwinding, and native reentry.
Do not retain stale pending-tail state across errors or public entries.

Focused proof: lisp_suite and lisp_auto_suite; deep mutual recursion both
forced-evaluator and AUTO-ineligible; call-budget exhaustion/recovery;
side-effect order and lifetime/error/native-reentry probes where existing
coverage is insufficient. Extend existing suites only for demonstrated
behavioral gaps. Use the current Lisp benchmark on baseline and candidate
for unchanged workloads; distinguish direct tail-call improvements from
AUTO hit timing. Update authored documentation for changed limits/behavior.

Endpoint: reviewed production patch with the reproduced failure repaired,
existing behavior preserved, and timing observations. E1 is independently
revertible and need not wait for any compiler prototype.

### E2. Stack-bounded non-tail depth

The commit's 6 MiB threshold measures frame-address displacement from the
outermost evaluator lambda. x2c-created threads use 8 MiB; arbitrary native
threads and caller stack consumption are not established by that fact.

Prototype the supplied policy against the normal main thread, an x2c thread,
and a native-created thread with explicit stack size, with realistic nested
caller stack use. Use inert temporary probes. Record where an error is
reported before native stack exhaustion, and which platform assumptions
remain. Preserve supported-toolchain portability; do not add a new general
stack-discovery subsystem merely to land the threshold.

Endpoint: choose the smallest proved stack policy, or keep the current
non-tail depth fence and record the limitation. Unsafe or unverified cases
must not be silently advertised as supported. If replacing the fence needs
materially larger machinery or changes native-caller obligations, present
the concrete alternatives to Gary. Tail calls remain deliverable either way.

### R1. One Pool per Error record

Owner: ErrorRegion and lib/error.x. Combine record String/List storage;
retain the separate Scope for wide boxes. Error.snapshot_in and since_in
already use one Pool for both roles. Reuse that ownership model; do not
introduce Var.transfer or merge Error frame chains.

Preserve borrowed/transient record lifetime, canonicalization and reclaiming
record-owned memory. Adjust construction, destruction, and explicit-owner
initializers together. Run error_suite, context_suite, logger_suite, and the
existing error-floor probes. Inspect transient/owner-boundary tests.
Endpoint: one record Pool and a small net deletion without new public API.

### R2. Shared raw recursive mutex operation

Owner: a narrow internal primitive beside lib/mutex.x; Error catch sites,
Logger, and Var descriptor registration consume it. Preserve each object's
pthread_once identity and lifecycle. It must be allocation-free and retain
raw fatal reporting; public Mutex.new is not the right operation.

Delete duplicated initialization/lock/unlock mechanics. Retain per-owner
policy and useful failure labels. Leave Pool's per-instance recursive mutex
alone. Run existing error/Logger recursion checks, var_suite, varops_suite,
mutex_suite, thread_suite, and error-floor probes as relevant to the diff.
Endpoint: three consumers share mechanics with no recursion or allocation
regression. Sequence after R1 because both edit error.x.

### R3. Fold identical Context export arms

Owner: lib/context.x. Share Block/Bytes/Buffer owns/move/return behavior
through their established representation conversions. Keep Array/Map cycle
identity, recursive export and rollback paths unchanged. Run context_suite.
Endpoint: repeated arms disappear with no new dispatch framework.

## Initial prototype portfolio

A prototype ends with a concrete patch and keep, revise, or stop decision.
Record net authored source change including replacement glue, surviving
owners/state, relevant generated output, and measurements where they decide
the design. No production backend toggle or parallel permanent implementation
is added merely to make an experiment convenient.

| ID | Finite experiment | Keep case and protected behavior |
| --- | --- | --- |
| P1 | Share common top-level classification between compiler.x shallow collection and parse.x full parsing. Stop after their common declaration categories. | Delete classification duplication; retain separate continuations, selective macro expansion/counts, collection order, source facts, diagnostics and scripts. No parser-recovery redesign. |
| P2 | Lower vseqcall alone to existing ordinary AST syntax; delete its emitter branch. | Exactly-once ordered argument evaluation, result lifetime and source origins survive; replacement is clearer and removes machinery. Check zero/multiple arguments, nested side effects, cache-shape assumptions and generated C. |
| P3 | Replace one lowering-driver mechanism after P2's AST decision, retaining cleanup as the terminal phase. | Prove actual repeated traversal/state disappears without extra policy. Preserve generated sibling ordering, identity fixed points, deep-chain behavior, region preanalysis and exit rewriting. Explain whether c.fixed/sibling rounds/cache walks really become unnecessary. |
| P4 | Measure SymTxn begin/commit/rollback on fixed macro-heavy units and REPL submissions. If material, prototype overlays for one map family. | Reduce total cost, not just begin cost; preserve failed rollback, successful/transient deletion, original borrowed map identity, source facts and lifetime. Account for added read/commit complexity before extrapolating. |
| P5 | Compare an isolated direct-mapped Match plan table with current LRU on the same hit, cold, collision-churn and nested-pin workloads. | Preserve lease/pin/generation/Pool-epoch safety and admission memos. Show useful simplification and workload evidence. Document any proposed eviction-policy change rather than updating its tests silently. |

P2 precedes P3; P1 and P4 edits serialize on compiler.x. P5 is independent.
Use existing focused fixtures and suites to establish equivalence. Compiler
prototypes compare a fixed corpus including current compiler/runtime source;
changes to generated C must have a explained semantic cause and relevant
runtime proof. A file rename or fewer source files is not evidence of fewer
passes or less work.

For P5, current MatchCache.acquire documents LRU and pressure only when all
entries are pinned. Colliding with one pinned direct slot cannot simply
return pressure while others are free. A transient plan can preserve execution
safety but does not preserve the whole documented eviction contract. Produce
that compatibility choice before any production replacement. Existing
match_cache_suite and match_plan_suite and benchmark lanes are starting
points; compare current and candidate cache policies directly. The historical
hit <=1.1x/cold <=1.3x figures are experimental targets, not new gates.

For P2/P3, preserve callable runtime cleanup registration AND local exit
cleanup, saved return values, nested frame order, catch lifetimes, volatile
pointees and source origins. The existing cleanup plan records declined
shared-exit and initializer-guard deletions; neither is reopened by changing
the lowering owner. Initializer guards still serve constructor-less units.

Promotion is routine when a prototype preserves its settled contract and
proves a proportionate improvement. A public policy change or roughly doubled
machinery is presented as a concrete decision before integration. Negative
results complete that investigation; they do not trigger an endless rewrite.

## Later queue: pursue after the initial results

| ID | Original item | Next useful work and dependency |
| --- | --- | --- |
| L1 | Remaining private emitter kinds | After P2, assess vcompound, vpostfix, dstrvalue and cleanup skeletons separately; preserve sequencing and cleanup contracts. Do not assume one representation fits all. |
| L2 | Complete transform/lambda/cleanup merger | After P3, decide whether one pass actually removes work; terminal cleanup may remain the correct boundary. |
| L3 | Remaining transaction maps | After P4, extend only the proved ownership/access model; otherwise close the full-frame replacement as declined. |
| L4 | Four typedef-chain walkers | Compare semantic stop identities, qualifiers, nested bases and builtin fallback. Consolidate shared walking mechanics without a universal policy framework. Shares compiler.x with P1/P4. |
| L5 | Six adapter memo sites | After lowering stabilizes, try a concrete net deletion that keeps differing cache result shapes and early declarations. Shares lambda.x with P3. |
| L6 | Ordered conversion rules | Prototype a small coherent rule group in expressions.x; preserve first-match, mutations, recursion and diagnostics. Current code is already ordered. |
| L7 | CLI metadata/setters | cli.x already has recognition/help metadata. First consolidate package eligibility; evaluate setter glue by net clarity/size, preserving response files and help output. |
| L8 | Build identity hash | Consolidate exact duplicate mechanics only; translation/action/script identities cover different inputs. Preserve resolved-path versus content distinctions and cache invalidation. |
| L9 | Project setter field table | Limit initial experiment to homogeneous target array fields. Retain kind/boolean/ignored-name/unknown-field policy. |
| L10 | Array/Map typed families | Complete at baseline via shared core-family instantiations. Verify continued sharing when reached; no replacement rewrite queued. |
| L11 | Recursive Match oracle to tests | Decide shipped optional API and include migration; no performance claim from moving an already optional module. Preserve test/benchmark oracle availability. |
| L12 | Autodiff to packages | Decide include/install migration, compiler/Lisp registration and coverage location. Preserve working examples and capabilities; removing tests from make check is a separate explicit choice. |
| L13 | Small public API retirement | Decide each item individually: ScopeStats maxima, Var.parse, List.subseq, Array.indexof, Var.fallback_* and Var.wide_*. Distinguish aliases, real features, telemetry and active internal cross-module owners. |
| L14 | Legacy macro body retirement | Decide source-compatibility policy and migration for documented former braced/parenthesized forms before removing recognition or fixtures. |

L11-L14 are queued decisions, not approved breakages. Bring a concrete
consumer/corpus inventory, migration patch outline, benefit and preserved
replacement to Gary when their turn arrives. Public API non-use inside this
repository alone never justifies removal.

## Integration, evidence and completion

Hold finished patches while peers are running; integrate a coherent batch
rather than publishing every tiny patch. E1 remains its own commit and may
land early if another task needs it. R1-R3 retain separate commits but share
publication evidence. Successful prototypes can form a later compiler/cache
batch; failed experiments remain evidence outside the shipped source.

At integration, fetch current origin/dev and apply authored patches against
their recorded bases, preserving upstream work. Rebuild immediately, review
and fix the combined authored diff, and inspect regenerated artifacts.
Performance-affecting batches use the existing performance-checkpoints.md
policy in a quiet window; report deltas without inventing new thresholds.

The root alone uses the repository integration/publication workflow,
including tools/land-dev and the final agent-pr-check evidence it owns.
Required check failures stop delivery. Diagnose from full logs; do not repeat
an unchanged gate in a loop. Documentation-only plan delivery uses doc-check.
No workers run broad gate components merely to publish their patch.

Publish implementation to dev, never force-push, and leave main unchanged.
Update this plan's task outcomes with delivered commits or prototype decisions
at each batch; record the current base and next file owners in .context/.
Generated bootstrap/docs are regenerated, never hand-edited or merged as
worker-authored source.

The initial milestone is complete when E1/R1-R3 are delivered or have a
specific evidence-based stop decision, E2/P1-P5 have finite dispositions, and
Gary has a concrete next batch to choose from the later queue. The full
campaign is complete when every row has a delivered, already-complete,
declined, or explicitly deferred disposition. Archive this plan with that
outcome; do not leave abandoned prototypes as permanent machinery.

## Plan review

Existing parameter evaluation and Lisp owners establish argument order and
value lifetime; tail evaluation must reuse them, not add a second validator.
Error's explicit-owner snapshots already establish combined Pool support.
Block conversions establish the Context export representation. pthread_once
and raw fatal paths establish mutex initialization/failure boundaries. The
compiler's binding, typing, origin, fixed-point and cleanup owners remain the
sources of facts; prototypes must remove duplicate work rather than recheck
those facts in a new ledger.

E1 reuses the existing evaluator/AUTO paths; R1-R3 delete duplicate ownership
or mechanics. P1 retains distinct semantic continuations. P2 uses canonical
AST and ordinary compiler operations. P3/P4/P5 must earn any lasting driver,
overlay or table through concrete deletion and measurements. No generic
visitor, callback rule engine, origin tracking, general transfer framework,
or second permanent backend is preapproved.

The intended source stays direct x2c: visible patterns/templates, ordinary
operations, and small helpers with an actual owner. The initial design adds
no new validator or dedicated diagnostic. Retain deliberate call-stack,
rollback, cache-pressure and raw native failure behavior. Focused regression
cases protect stack exhaustion, wrong evaluation order, lost rollback,
use-after-free or unsafe mutex recursion; they are not tests for an internal
framework. Each delivered change ends with authored-diff review and fixes
before existing publication validation.
