# Deferred code, scoped memoization, and unit assembly

> Status: active
> Planning and source investigation only; no compiler implementation or
> performance experiment has been completed for this plan.
> Gary authorized publishing this planning document to `origin/dev` so a
> fresh session can resume it. That instruction does not start the compiler
> implementation. Obtain an execution instruction before changing production
> code, and establish that the other campaign's benchmarks have finished
> before running builds or measurements.

## Goal and user intent

Make the compiler cleaner, shorter, faster, and easier to maintain by
consolidating the representation and bookkeeping of code generated for later
insertion, and by sharing memoization for substantial computations whose
stable inputs determine their outputs. Use that foundation to simplify
compilation-unit assembly. Renaming queues or putting a facade over all of
them is insufficient: remove duplicate owners, stored representations,
repeated computation, and unnecessary traversal.

The investigation began with function/scope augmentation and cleanup, then
expanded to initialization and the assembly of a complete source unit. Gary
proposed a small number of semantic destinations instead of incidental
early/late insertion conventions. He then asked that this be reflected in
the internal data model: numerous arrays and maps with unrelated payload
conventions may represent the same underlying pending-code obligation.

Gary's analogy is one environment model with ordinary scoped frames, rather
than separate environments for every category of value. A shared model can
retain necessary scopes and indexes without giving each producer independent
bookkeeping. One physical global array is not a requirement.

The immutability extension concerns meaningful compiler computations with
stable input/output relationships. Concatenation was an illustration of a
functional operation, not a request to cache low-level List operations.
Exploit the hierarchy of lifetimes and acyclic/tree-shaped representations
the compiler already establishes. Do not substitute a general purity checker
or complex invalidation system for those known boundaries.

The motivating use case is a debuggable decorator that could register the
types and addresses of parameters and locals, maintain per-invocation frames,
respect lifetime validity, and clean up on exits, possibly with cooperative
inspection checkpoints. It is a design exercise, not a requested debugger
implementation. The abstraction should make that future use straightforward
without instrumenting every operation or adding another cleanup walker.

## Baseline, succession, and inspection limits

- Initial audit: clean `/Users/gary/Git/x2c`, `dev` at
  `0bba0aedb98f6c95f61d0203e7084d19600c2af2`.
- Gary then selected `/Users/gary/.codex/worktrees/7a13/x2c`, branch
  `codex/automatic-interfaces`, as the prospective implementation baseline.
  Investigation first used `2050afdea54de0320f74c37d8752c5da3bae97df`, then
  `3f2ad976efe24d316cca16a2fccff1c197e90a06`.
- Once that worktree developed uncommitted changes, further evidence was
  read from committed `3f2ad976`, not its changing files.
- Fetching `origin/dev` for this document found it at `3f2ad976`. The
  automatic-interface architecture has therefore landed. This plan is based
  on that architecture, not the older visibility-pragma design.
- Follow-up review fetched and fast-forwarded to
  `00389e131bf1b5c5a33afa59f299746fc3fc5bbb` (`fix retained macro bindings and
  package builds`). The changes below refine the compatibility and reuse
  contracts; they do not implement the pending-code consolidation. The
  generation, cache, cleanup, transform, transaction, generic memo, Scope, and
  Match-cache owners were unchanged by that commit.
- Source and checked-in fixtures were inspected. No behavior probe, compiler
  test run, LOC prototype, allocation measurement, or timing result establishes
  the proposed changes' benefit yet. No defect is claimed merely from finding
  multiple containers or traversals.

Read current [repository instructions](../AGENTS.md),
[planning guidance](../agents/skills/plan-x2c-change/SKILL.md),
[simplification guidance](../agents/skills/simplify-x2c-source/SKILL.md), and
[plan conventions](README.md) when resuming. Reconcile this plan with the actual
current `origin/dev`; source symbols below are the primary locators. Original
line numbers are evidence at `3f2ad976`; the follow-up below describes `00389e13`.

### Reconciliation with retained-macro and package repairs

Four landed changes matter to this design:

1. **Linked meta reuse distinguishes provider freshness from definition
   freshness.** `Compiler.linked_meta_definitions_current` in
   [collect.x](../src/collect.x) first uses existing provider/source proofs,
   then can compare a retained digest of the sorted definition-hash rows.
   `add_linked_meta_provider_hashes` appends that digest to the existing source
   proof for relevant providers. `Scan.file` in
   [meta-project.x](../src/meta-project.x) uses it to avoid a project helper
   for compiler-owned definitions that still match; `_linked_texts_match` in
   [meta-native.x](../src/meta-native.x) uses it for provider references.
   This is existing reuse at a meaningful boundary. Preserve both validity
   questions and their callers: definition freshness is not a universal
   replacement for source/dependency freshness or interface invalidation.
2. **Retained native stubs transfer their storage to the Lisp session.**
   `_install_stub` now calls `Lisp.bind` instead of `Lisp.set_global`.
   [Lisp.bind](../lib/lisp.x) moves the `Func` into the session's Scope;
   `set_global` alone borrows value referents. A shared pending or memo owner
   must preserve that established ownership transfer. The move does not
   automatically transfer the owners of every value referenced by the Func,
   including its signature graph.
3. **Retained catch syntax still needs occurrence-specific resolution.**
   `_bind_catchcases` in [parse.x](../src/parse.x) now resolves the pattern
   before introducing catch-arm bindings. Keep this resolution when reusing a
   prepared macro or recipe. Syntax immutability alone does not establish that
   the fully bound catch is reusable in a different expansion environment.
4. **Implementation keyword aliases are file-local.**
   [private-keywords.x](../lib/private-keywords.x) exports the loop decorator,
   while files that use its shorthand declare `static keyword loop` locally.
   Do not reconstruct or memoize the includer's syntax environment by exporting
   the implementation alias together with the reusable decorator.

`keyword-identifier` now exercises an ordinary `loop` identifier after an
include, and `macro-catch-binders` includes a catch inside a generated Unit
function. Include these cases in the relevant future focused validation. This
review inspected source and fixture changes; it did not rerun compiler tests,
package builds, or benchmarks or infer that other benchmark work had finished.

## Existing cooperation to preserve

The compiler already has important common owners:

- `FileWalk.select_public` in [collect.x](../src/collect.x), around line 465,
  selects public declarations and closes over required type families.
  `publishes_typedef` and `publishes_type_family` expose that answer.
  Header generation consumes it; `interface_text` serializes the collected
  contribution instead of independently reconstructing the public interface.
- `_replay_cached` and `replay_package_imports` in collect.x preserve ordered
  declaration segments, includes, and compile-time effects. Full parsing
  resets macro state and installs included effects at the include position.
  Static definitions and retained declaration recipes keep their owning
  source/session context.
- `_forward_declarations` in [generate.x](../src/generate.x) serves both
  header and source. Static type selection and prototype sharing are already
  consolidated; do not count them as proposed deletions.
- `Walk` in [cleanup.x](../src/cleanup.x) owns region-aware exit rewriting.
  Defer, try/finally, and static-initialization regions cooperate there.
  Return, break, continue, and goto depend on region ancestry and transfer
  boundaries, not simply on an unconditional end-of-block statement.
- `SymTxn` in [symbols.x](../src/symbols.x) owns semantic rollback, including
  generated effects for macro value applications. Do not introduce a parallel
  rollback protocol.
- [adapter-memo.x](../src/adapter-memo.x) already provides generic `$memo`
  and the `$adapter.memo` specialization. Callables reuse generated adapters;
  protocol analysis uses `$memo` for ancestry, ordering, rejection, and member
  selection. Some answers depend on mutable registries and are invalidated
  with those registries.
- Macro definitions retain template, pattern, rebuild, hole-projection, and
  capture information. `_try_macro` in [macros.x](../src/macros.x), around
  line 2627, decodes an imported template on first use and stores the decoded
  definition through the semantic write log.
- [macro-value.x](../lib/macro-value.x) and
  [match-cache.x](../lib/match-cache.x) already reuse prepared recognition
  plans. Subject-dependent recognition remains per-use. Canonical Lists and
  [ast-rewrite.x](../src/ast-rewrite.x) preserve structural sharing and return
  unchanged input identities where possible.

The new design should consume these guarantees rather than check or rebuild
them in a new unit-layout layer.

## Representation inventory and consolidation candidates

| Current representation | Payload, owner, and use | Proposed treatment |
| --- | --- | --- |
| `Compiler.early_decls` | Compiler-local ordered generated declarations; lowering drains newly produced siblings to a fixed point | First client of common pending-code bookkeeping |
| `Compiler.inits` | Ordered `(phase statement)` entries; statements must already be lowered | First client; preserve explicit phase/stage contract |
| Cache `initializers` | Initially `(binding assignment)`, enriched to `(binding assignment helper arms)` | Give deferred static work a consistent record contract |
| `StaticQueue.pending/state/phases` | Definitions, traversal state, and selected phase indexed by the same binding | Consolidate per-binding scheduling facts; retain dependency order |
| Source/header cache declaration arrays | Lowered slots, guards, and helper definitions awaiting local assembly | Evaluate as contribution clients after ownership/placement is explicit |
| `declaration_effects` | Deferred Lisp forms with source key, source span, syntax, and defining context | Related work; reuse representation only if context and effect semantics survive |
| `pending_inline_bodies` | Provider compiler, source text, symbol maps, statics, and hashes; shared among related compilers | Deferred semantic work with an existing session owner; do not flatten ownership |
| `meta_group` | Tagged function, static, and later-placeholder rows for meta generation | Existing tagged representation; assess reuse without changing staging |
| `Walk.regions` | Active cleanup statements and markers used for multiple control-flow exits | Preserve active scope/ancestry semantics; not a consume-once queue |
| Literal identities, dependency maps, traversal worklists | Interning indexes, semantic relationships, or temporary algorithm state | Do not migrate merely because they are arrays/maps |

Evidence: `Compiler.add_early` and `add_init`, compiler.x around 2270;
`SymTxn._save_effects/_restore_effects`, symbols.x around 1296/1443;
`Compiler._rewrite_statics`, cache.x around 159;
`StaticQueue`, cache.x around 619;
`Compiler._share_unit/_init_queues`, compiler.x around 2758/2779;
`Compiler._code_effects`, macros.x around 4196.

Generated declarations and initialization statements currently have separate
arrays, append APIs, initialization, and rollback counts despite sharing an
ordered pending-work contract. Conversely, pending inline bodies are shared
across child compilers while these queues are separately initialized. The
common abstraction must make actual ownership explicit.

`StaticQueue.state` and `phases` offer a bounded representation experiment:
visiting, finished-ordinary, and finished-late may replace two independent
maps. More generally, a binding index can reference one scheduling record.
Account for record allocations before declaring an improvement.

## Intended model

Separate three concepts while sharing their bookkeeping:

1. **Reusable computation:** operation plus complete stable inputs yields
   reusable code, analysis, or a prepared recipe.
2. **Pending contribution:** code or a recipe reference plus destination and
   occurrence-specific placement context.
3. **Assembly:** consumes contributions under established order and lifecycle
   rules, using the existing public-interface and dependency owners.

Several contributions may reference one computed result. Consuming an
insertion is different from computing a value. Fresh bindings and invocation
origins belong to the occurrence, not automatically to the reusable payload.

The pending-code contract must express destination, accepted AST stage, code,
and necessary placement context. Encode facts once: if the destination implies
the stage, do not store both independently; if the AST already carries a
binding or origin, do not duplicate it in another metadata map. Producer
category is not a storage policy unless a consumer needs it.

Semantic destinations include public declarations, generated declarations,
source support, file initialization phases, body entry, and declaration point.
The public-interface collector decides visibility. Assembly decides placement.
Cache registries retain identity/deduplication duties while supplying storage
and initialization contributions.

Use a common owner per appropriate compiler/session lifetime, with ordered
entries and indexes into those entries as needed. Do not require one physical
global array. An interleaved append-only log can retain already-consumed
declarations until initialization completes; compare that cost with compact
storage or phase-local consumption before choosing the representation.

The first concrete design must settle append order, consumption, additions
made while draining, checkpoint/rollback, index validity, and release of
consumed payloads. A single truncation mark suffices only for append-only
effects: changing earlier records, indexes, or consumption cursors requires
the corresponding rollback behavior. Preserve current fixed-point generation.

## Shared scoped memoization

Start with the existing `$memo`, not a new cache framework. The contract is:

```text
memo owner + operation identity + complete stable inputs -> reusable result
```

The owner supplies the validity boundary. Different substantial computations
can use operation-tagged keys in a shared memo when their ownership matches.
Known compiler contracts establish stability; do not recursively rediscover
purity or deep immutability at every lookup.

The landed linked-meta definition digest is a concrete example of such a
boundary. Count it as existing cooperation, and reuse its established evidence
when evaluating meta-generation candidates. A new memo around filesystem or
provider checks still needs the current validity contract; a path alone is not
an immutable input. Do not merge source-freshness and definition-freshness
answers under the same operation identity.

Inventory actual computations using: result, complete inputs, point of input
stability, lifetime, existing preparation/cache, repeated callers, and effects.
Investigate prepared decorator/template analysis, structural projections,
generated adapter recipes, and analysis against completed interface/type
information. These are candidate families, not established cache misses or
measured wins. Choose real repeated computations before generalizing the API.

Keep two contracts distinct:

- Pure result reuse: the same complete stable inputs permit the same result.
- Once-per-owner generation: a semantic key selects a helper whose binding and
  registration must occur once within its unit, under existing transactions.

A shared implementation may support both, but a cache hit cannot suppress
required effects or publish bindings from a rolled-back expansion. Pure
results that contain provisional semantic identities are not automatically
safe to retain across rollback.

Immutable templates do not imply pure full expansion. Fresh names, scope
resolution, Lisp/meta evaluation, diagnostics, origins, and generated effects
can be application-specific. Reuse the prepared computation or structural
result at the boundary that is actually stable. `freeze_declaration_syntax`
reads semantic facts and origins; thawing installs facts, cache entries, and
origins. Do not memoize those whole operations by syntax identity alone.

Canonical List cells can hold mutable objects, but this is an operation-level
input contract, not a reason to build general defensive machinery. An operation
observing only immutable structure differs from one inspecting mutable contents.
Use the existing [Scope](../lib/scope.x) and pool ownership contracts. Retain
keys and results only for their valid lifetime; do not infer process lifetime
from pointer identity. Prefer a scope/phase boundary over dependency-version
graphs. The existing Match cache demonstrates lifetime handling but should not
be copied wholesale into a lightweight compiler memo.

Canonicalization shares equal output storage; memoization avoids repeating the
computation. Their benefits differ. Do not target low-level append/concatenation
as the campaign's objective, cache every AST operation, or replace already
effective preparation caches just to unify names.

## Assembly consumers and deletions

Use the common representation to make the pipeline explicit:

```text
select the public projection and preserve ordered source
materialize cache storage and initialization contributions
assemble file initialization
place function bodies and required declarations
assemble final source text and main entry setup
emit
```

Concrete deletion targets:

- Combine `_primary_include`, source spacing, and `_patch_main` into final
  source assembly. This can remove two complete flat source traversals and
  their intermediate lists. Discover both runtime-header anchors together
  where that shortens the implementation. Preserve existing whitespace,
  banners, guards, include ordering, and main setup.
- Replace `Partition.source`, which is not the emitted source, with the facts
  its consumers need: whether source content started and conditional-group
  source membership. Retain ancestry for pending includes until promotion is
  settled. Pending markers do not set source-started. Preserve the independent
  source projection. Keep this change only if its replacement bookkeeping is
  simpler; no large LOC saving has been demonstrated.
- Share parameter-escape body insertion with the existing `_prepend_setup`
  operation. Under automatic interfaces, its current `static` visibility must
  be accounted for when choosing the shared owner; do not assume a cross-file
  call requires no declaration/visibility change. Count all resulting glue.
- Remove superseded queue fields, APIs, transaction counts, conversions, and
  record-shape conventions as clients migrate. A wrapper retaining all of the
  old machinery is incomplete.

Do not blindly fuse cache support insertion with file-init insertion. More
than 512 cache assignments can create helper functions inside the cache
prelude. Subsequent `_file_init` may insert its guard and synthetic initializer
between slots and those helpers; reachability analysis sees the expanded
source. Preserve that conceptual stream without introducing a costly virtual
source framework solely to avoid materialization.

Runtime initialization preserves entry, run-once guard, early, middle, authored
body, late, and shutdown ordering; protocol setup retains its prerequisite
role. These runtime phases differ from source visibility and compile-time
effect activation. Header cache storage remains private to each native unit.

## Behavioral invariants

- Cold collection and warm interface replay have the same visible contribution.
  Includes activate compile-time definitions at their existing source points;
  later Lisp/declaration effects do not run during metadata lookahead.
- Static definitions, deferred recipes, macro syntax, and provider sessions
  retain their current ownership. Macro definition identity, rather than a
  name alone, determines reusable preparation across redefinitions.
- Binding, hygiene, diagnostics, transaction rollback, and per-invocation
  origins remain correct on both memo hits and misses.
- Retained host function storage follows `Lisp.bind` session ownership;
  catch patterns retain their resolution before catch binding; implementation
  keyword aliases remain file-local even when their decorator is public.
- Linked meta definition reuse retains the current distinction between
  unchanged definitions and unchanged provider sources/dependencies. Preserve
  avoidance of unnecessary helper generation without weakening other consumers'
  freshness requirements.
- Native directives retain their effects. Public inline bodies preserve their
  source macro state; ordinary bodies obey `#undef` boundaries and conditional
  arms. Captured initializer helpers stay at their source positions.
- Dependency-before-consumer static initialization and late-phase propagation
  remain stable; independent roots retain source order and cycles retain their
  existing diagnostic.
- Entry setup keeps its transformation epoch and execution order. Parameter
  cell setup precedes normalization; parameter escape setup is discovered
  later but currently executes before earlier-prepended setup. A single queue's
  discovery order is not an execution-order specification.
- Local registrations occur when declarations make their bindings/values
  usable, not indiscriminately at block entry. Cleanup retains normal exit,
  return, break/continue boundaries, goto ancestry, exceptions, and finally
  behavior through existing owners.

## Execution sequence and evidence

These are checkpoints in one connected change, not mandatory separate releases.

1. After execution is requested, fetch current `origin/dev`, establish an
   isolated worktree and delivery role under current guidance, and reconcile
   this plan with final inclusion/memo changes. Do not use an old campaign
   worktree as the current baseline. Confirm the CPU-intensive campaign ended.
2. Complete a bounded producer/consumer inventory for the first clients and
   meaningful memo candidates. Select the concrete record/storage design using
   the contracts above. Record decisions in this plan, with the code each new
   piece replaces. No new user decision is needed for routine implementation
   choices within these compatibility requirements.
3. Establish the required usable compiler baseline and focused existing
   behavior evidence. Prototype shared pending bookkeeping with generated
   declarations, file initialization, and static initializer metadata. Delete
   replaced owners in the same implementation.
4. Apply shared scoped memoization to selected substantial computations.
   Demonstrate repeated inputs and avoided work; distinguish migrated existing
   caches from genuinely new reuse. Verify hits, misses, ownership, and rollback.
5. Simplify assembly using the resulting destinations and existing semantic
   owners. Include shadow-source replacement and scheduler-state consolidation
   only where the completed replacement earns its cost.
6. Review and fix the complete authored diff for duplicated guarantees,
   unnecessary fields, adapters, dispatch, traversals, and non-idiomatic code.
   Update affected internal documentation and generated artifacts through
   repository targets. Do this source review before publication proof.
7. Run relevant focused checks, performance comparisons, and the existing
   publication validation/delivery workflow from current AGENTS.md. Do not add
   a recurring gate. Record exact revisions, commands, results, and remaining
   limits, then update/archive this plan when its implementation is complete.

Use existing compiler fixtures and probes first:

| Concern | Existing starting points |
| --- | --- |
| Cold/warm interfaces and ordering | `ordinary-interface-cold`, `ordinary-interface-warm`, `ordinary-interface-unit-order`, `ordinary-interface-unit-order-warm`, `ordinary-interface-meta-order` |
| Private compile-time definitions and context | `ordinary-interface-static-macro`, `ordinary-interface-static-keyword`, `ordinary-interface-meta-static-lisp`, `keyword-alias-included`, `keyword-identifier`, `meta-included-file-constants-shadowed` |
| Recovery and identity | `macro-enumerator-rollback`, `macro-type-fields-rollback`, `macro-catch-binders`, local macro and hygiene fixtures |
| Native ordering and captured initialization | `header-promoted-include-macros`, `static-native-source`, `c-macro-redefinition`, `initializer-native-identity` |
| Initialization and dependencies | `conditional-file-init`, `conditional-type-initializer`, `conditional-type-initializer-compiled`, `cache-reachability`, `literal-cache-init`, `private-typedef-order` |
| Lifecycle | Existing defer, try/finally, scoped allocation, return/break/continue/goto fixtures; select by changed consumers |

Fixtures live under [unittest/compiler-fixtures](../unittest/compiler-fixtures).
Read [test instructions](../unittest/AGENTS.md) before running them. Compare
generated C/header output, diagnostics/status, and runtime expectations. Check
coverage of large-cache batching and units without functions. Add a focused
fixture only for a public invariant not already covered, not to mirror the new
containers. No new negative fixture is prescribed by this plan.

If the implementation changes linked-meta reuse, provider proofs, or retained
native stubs, also select relevant existing coverage from
[run-meta-helper.sh](../unittest/probes/run-meta-helper.sh),
[run-meta-cache-key.sh](../unittest/probes/run-meta-cache-key.sh), and
[run-package-install.sh](../unittest/probes/run-package-install.sh). Inspect
their actual cases before choosing focused commands; their existence is not a
claim that every new digest/ownership boundary has dedicated coverage. These
are conditional implementation checks, not additions to recurring gates.

Follow [performance guidance](../agents/performance-checkpoints.md) when the
machine is available. Compare converged toolchains with valid, nonempty
preludes and identical effective inputs; bootstrap/interface fallback can swamp
the effect being measured. Use alternating runs where appropriate. Observe
cache hits/misses, avoided computation, allocations, and retained/peak memory
as well as elapsed/instruction cost. Temporary measurement instrumentation
does not become a new permanent registry by default.

## Acceptance, stopping rules, and fresh-session handoff

Acceptance requires a net reduction in authored production code including all
new infrastructure, fewer independent bookkeeping paths, preserved observable
behavior, and no material performance regression. Report generated-code changes
separately from authored savings. Fewer traversals is static evidence, not a
measured speedup. Compiler throughput and memory may improve; generated-program
runtime should remain unchanged by a behavior-preserving bookkeeping refactor.

Reject or narrow a prototype that adds more representation/dispatch than it
removes. Remove memo applications with insufficient reuse or excessive retained
memory. Do not claim large savings from the current four-line insertion overlap
or the shadow-source candidate; all new visibility and ownership glue counts.
Conversely, the existence of small current helpers does not reject the broader
shared-data-model hypothesis without testing real combined clients.

A fresh session should read this plan, current AGENTS.md and the named source
owners, verify current `origin/dev`, and ask only for missing execution
authorization or consequential scope changes. The next technical work is the
bounded representation/client comparison, not another broad architecture audit.
The original audit's cleanup findings remain context; implementation must not
quietly expand into a debugger, universal effect engine, or unrelated campaign.

Publishing this document uses documentation-only validation. The CPU restraint
from the conversation remains relevant to future compiler experiments until the
other benchmark campaign is known to have finished. Do not interpret a published
inclusion commit as proof that all benchmarking is finished.

## Plan review

Collection establishes ordered public contributions and type visibility;
binding establishes semantic identities; Scope/pools establish lifetimes;
transactions establish rollback; existing dependency and cleanup owners
establish their respective orders. Proposed consumers use those facts without
revalidating them. Pure-result memoization requires complete stable inputs by
the operation's contract, not speculative purity flags or repeated validation.

The design reuses canonical ASTs, prepared macro records, `$memo`, semantic
transactions, interface selection, forward declarations, body insertion, and
cleanup. It targets duplicate queues/snapshots, shape-changing pending records,
parallel scheduling maps, discarded source construction, repeated expensive
computations, and final assembly passes. Each new field, index, helper, or memo
must replace necessary existing work and have an explicit owner and lifetime.

Ordinary x2c records, Lists, match/templates, decorators, and scope-owned maps
should express the result directly. A generic event bus, dependency framework,
global scheduler, or universal cache is not justified by this plan. Concrete
storage and memo-client choices remain bounded implementation experiments,
with acceptance rules stated above rather than unsupported benefit claims.

No new validator, dedicated diagnostic, or negative fixture is proposed.
Preserve existing deliberate failures and add only missing behavioral coverage
identified while implementing. Review and simplify the final source before
publication validation; green tests do not justify unnecessary machinery.
