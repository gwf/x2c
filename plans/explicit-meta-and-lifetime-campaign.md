> Status: blocked
> Updated September 23, 2026. This is the planning handoff for the deferred
> next phase. Stabilization is locally validated but has not been delivered
> to `dev`. Implementation remains on hold pending that delivery and Gary's
> resource/scope decision. It must not start automatically.

# Next phase: explicit meta calls, lifetimes, and computed values

Deliver the major capabilities deferred while the current campaign closes
stabilization. This plan records their scope and dependencies for the next
planning agent; it does not dispatch more work into the active campaign.
It replaces the earlier detailed execution schedule in this file. The
language and ownership decisions below remain the intended direction.

## Handoff boundary

This plan, the [active stabilization plan](post-merge-stabilization-2026-09-23.md),
and the earlier [heap-object investigation](meta-heap-objects.md) now live in
the same repository. Local validation does not establish delivery. Before
implementing this phase, confirm the stabilization commit actually on `dev`,
review its remaining-item disposition, and obtain Gary's resource/scope
decision. Preserve these files' newer status if another checkout has moved on.

## Work already owned by stabilization

The active [post-merge stabilization plan](post-merge-stabilization-2026-09-23.md)
owns the following repairs. Its orchestrator owns their remaining fixes,
integration, validation, and delivery to `dev`. These are expected outputs
of that campaign, not claims that every item is already complete.

| Area | What stabilization is responsible for addressing |
| --- | --- |
| Meta execution and conversions (C1-C4) | Destination conversions, effectful and discarded expressions, typed/reference-bearing Func calls, and persistent function-local meta statics. |
| Binding and native layouts (F1-F4) | Foreign package tag ownership, lexical template binding, same-basename source identity, and safe native record layout handling. Packed layouts are unsupported and produce a direct compile error. |
| Storage and build correctness (S1-S3) | Static initializer classification, Scope/Pool result and retention summaries, and native-module relinking after library changes. |
| Tools and maintained surfaces (M1-M5) | Graph preload/allocation reporting, compiler-selected public definitions, generated docs/API inventory, the full sanitizer invocation, editor grammar, and evidence-backed status. |
| Integration and publication | Relevant packages and HTTP/JSON, native modules, graph/parity, sanitizers, documentation, installed compiler consumers, affected interface/bootstrap reproducibility, final-tree validation, and verified delivery to dev. |

The current campaign also owns regressions found in its repairs: the mixed
Scope/Pool helper summary, mixed Symbol/numeric conditional conversion, and
initial Lisp regeneration after the Func changes. Their exact repair status
may advance while this document is being read. Do not create competing fixes
or carry them into this phase merely because an old status note lists them.

Before implementation, obtain the actual stabilization delivery commit and
remaining-item disposition from its orchestrator, and start from that delivered
`dev` state. Local commits and passing focused tests are not publication proof.
If an item above remains unresolved, identify it as a stabilization dependency
rather than silently assuming it works or redispatching the original campaign.
Planning may proceed now against the intended post-stabilization baseline.

## 1. Make compile-time entry explicit

In ordinary source, `$f(args)` executes at compile time and inserts its
result; bare `f(args)` calls the compiled runtime function. Remove x2c's
automatic interpreter folding of ordinary calls. Native C optimization
remains available. Plain helper calls inside an executing meta body inherit
that phase, so authors do not add `$` to every internal helper invocation.

An explicit evaluation or insertion failure is a diagnostic, never a silent
runtime fallback. Existing macro forms, Lisp syntax, template holes, and
compiler-only function restrictions retain their contracts. Audit intended
precomputation sites by binding and context and migrate them explicitly.

This intentionally replaces stabilization's automatic-fold eligibility
policy. Preserve its conversion, exactly-once evaluation, Func, static-storage,
and compiler-only reachability repairs. Delete only machinery made obsolete
by removing automatic folding.

## 2. Support explicit temporary lifetimes in meta code

Make the existing Scope/Context model usable for temporary meta allocations.
Provide reliable cleanup for the relevant `defer` and `$scope` forms, including
normal exits, returns, loop transfers, and Error unwinding. Keep evaluator
bookkeeping under its own established owners so user cleanup cannot invalidate
bindings, automatic storage, or persistent session state.

Allocation follows the active Scope; the evaluator session is the default.
Do not add an implicit temporary Scope around every function call. Escaping
values use existing ownership movement or Context graph export. Cover writes
into caller-owned containers and persistent storage as well as returned values.
Raw pointers do not supply a description of ownership for all their fields.

Reuse the shared region analysis and the stabilization ownership repairs.
Live graph export preserves supported identities and aliases; materialization
into generated source is a separate operation with a narrower result contract.

## 3. Materialize recursively computed collections

An explicit meta call may return a computed Array or Map containing supported
scalar values, Strings, Symbols, Lists, nested collections, and boxed values.
Preserve types/tags, null and empty distinctions, and ordinary Map key semantics.
Inspect the computed value rather than deciding solely from its return type.

Support finite trees of mutable nodes initially. Diagnose cycles and shared
mutable children rather than silently changing aliasing. Every runtime
execution of the emitted expression gets fresh mutable roots and descendants.
Only transitively immutable subtrees may share existing literal cache entries.
Native addresses and unsupported callables cannot become source constants.

Route results through ordinary literal/cache and collection-lowering owners;
repair the stage handoff instead of adding another emitter or cache. Map
emission and cache assignment must be deterministic without promising runtime
iteration order. Preserve existing distinctions between syntax Lists and data.

## 4. Enable heap allocation and typed heap objects in meta code

Expose the needed Scope allocation operations: malloc, calloc, memdup,
realloc, and free, together with the explicit ownership operations required
by the lifetime work. Preserve existing allocation and resize ownership
semantics. Extend shared region facts for known invalid free/resize and stale
references; do not add an allocation registry or claim complete alias safety.

Support `sizeof` through existing scalar/layout facts and typed heap
constructors/methods through native storage. Intermediate heap pointers may
flow between meta helpers; final inserted results must satisfy the value
materialization contract. Prevent evaluator addresses from leaking into
emitted constants. Do not silently box an unsupported unit-defined class as
an unrelated generic pointer.

The older [heap-object proposal](meta-heap-objects.md) supplies investigation
context. Its speculative folding rules and blanket deferral of Scope cleanup
are superseded by this coordinated direction. Bootstrap new native targets
before adding in-repository compile-time consumers of them.

## 5. Prove the benefit through bounded internal adoption

Replace at least one real compiler table's special AST-construction machinery
with a meta function returning ordinary computed data. The scalar/type-row
tables are candidates, not a mandate to rewrite a particular subsystem.

Simplify a real temporary-container workload using explicit scope cleanup and
correct export of surviving results. The two demonstrations may share a caller
if that is natural. Show concrete code removal and relevant memory or translation
cost evidence; avoid a broad cleanup campaign or speculative library migration.
Update the book with the phase rule, lifetime contract, and working examples.

## Sequence and completion boundary

After stabilization delivery and the resource/scope decision, implement explicit
phase selection first. Lifetime support and recursive materialization are the
next foundations; sequence edits to shared compiler owners. Heap support follows
those foundations, and internal adoption follows a compiler that contains the
required native targets. Keep implementation with bounded workers and the
coordinator responsible for integration and delivery.

Use focused evidence for phase selection, cleanup/escape behavior, result
freshness and caching, deterministic generation, and native/evaluator parity.
Reuse stabilization's validated behavior and fixtures instead of repeating its
whole discovery campaign. Review the authored and generated diff, then apply
existing publication requirements to the final tree. Add no recurring gate or
new broad review process. Production promotion of `main` remains separate.

General mutable-graph reconstruction preserving aliases, isolated meta pools,
unit-defined meta Var protocol registration, broader lifetime/effect inference,
and unrelated cleanup remain backlog. They are not prerequisites for completing
the five pieces above. Any further split for resource reasons must name the
capability being deferred explicitly.

## Plan review

Reuse existing type, binding, layout, conversion, cleanup, region, literal,
cache, and constructor owners. Stabilization establishes the repaired baseline;
this phase extends its capabilities rather than duplicating its implementation.
Remove automatic-fold machinery and demonstrated special construction code.
New cleanup support and transient result identity tracking serve concrete
lifetime and aliasing requirements, not a general framework. Diagnostics protect
explicit phase behavior, representable values, valid ownership, class identity,
and native crossings; no extra syntax-origin validator or allocation tracker
is planned. Detailed work packets should preserve these boundaries.
