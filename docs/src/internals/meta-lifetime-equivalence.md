# Meta-function Lifetime Equivalence

> Research status, September 2026. This report records a candidate static
> guarantee and the evidence behind it. It is not yet a language promise or
> an implementation plan.

## Executive conclusion

x2c has the pieces for a strong, mechanically checkable memory-lifetime
guarantee for meta functions. The most defensible form is not that native and
interpreted execution have identical call graphs. It is that both executions
simulate the same abstract ownership-effect graph after native activations are
mapped onto evaluator frames and the native ambient `Scope` is mapped onto the
Lisp session `Scope`.

Under that mapping, the evaluator generally coarsens lifetimes: a native local
becomes a word-machine slot or evaluator cell, and storage which native
execution might release earlier can remain owned by the session until the
session ends. Coarsening is safe when it never shortens an owner's lifetime,
never loses a finalizer, and never introduces an unmodelled retaining edge.

The candidate guarantee is therefore:

> A dual-form meta function which is region-clean under complete program
> summaries is lifetime-safe in the evaluator when every reachable
> compile-time binding has the same ownership effect as, or a safe refinement
> of, its native counterpart.

This conclusion becomes compelling if x2c also adopts one construction
invariant for runtime objects: every object is owned by a `Scope`, and every
resource requiring work beyond memory reclamation has exact-once finalization
attached to that ownership. Together, the two conditions make native region
analysis reusable as a proof about interpreted execution rather than requiring
a second borrow checker for the interpreter.

The guarantee is not established today. Region findings are warnings,
unresolved callees currently receive an empty effect summary, compile-time
adapters do not carry checked ownership summaries, and compile-time-only meta
functions have no native form to compare. These are finite proof obligations,
not evidence against the model.

## Scope of the claim

This research deliberately excludes control and native behavior which would
need additional modelling:

- exceptions, `defer`, cleanup transfers, and other non-local jumps;
- unchecked pointer arithmetic, arbitrary pointer casts, and unmodelled raw
  dereferences;
- callbacks or function pointers without a declared ownership effect; and
- native allocation or release outside the `Scope` and finalizer contracts.

The claim covers dual-form meta functions: functions which retain a native AST
after their compile-time definition is installed. A compile-time-only `meta`
function which reaches a `Meta` operation is removed from the emitted runtime
AST. It consequently has no native execution against which equivalence can be
proved without first constructing an analysis-only native form.

The report distinguishes three properties which are easy to conflate:

1. **Storage reclamation:** the bytes backing an object are eventually freed.
2. **Resource finalization:** an operation such as closing a handle or
   destroying a mutex runs exactly once before its storage is reclaimed.
3. **Reference safety:** no live value can reach storage after its owner ends.

`Scope` supplies the first property by construction. A finalized allocation or
a proved cleanup obligation supplies the second. Region and ownership analysis
address the third.

## The native region analysis

The [region model](../guide/regions.md) starts from a simple invariant: a value
allocated inside a region must not remain reachable after that region ends.
The compiler analyzes bound and typed AST before transform lowering, while
`$scope`, `$auto`, retain/release, and their closing forms are still visible.

For each function, `src/regions.x` derives a summary containing two kinds of
fact:

- whether the function returns fresh storage; and
- where each parameter may be sunk: into the return value, a static, an object
  reached through another parameter, or an unknown pointer.

The analysis walks all bodies to a fixpoint because one function's summary
depends on its callees. The `region-escapes` command in `x2c-graph` performs
the corresponding whole-project computation, allowing summaries from one
unit to inform callers in another. This is the holistic part of the current
system: the source graph supplies the complete inter-unit call relation, while
the region analysis supplies ownership effects on those edges.

The current translation pass remains advisory. `Compiler.transform` always
calls `Compiler.check_regions`, but the findings are warnings and do not
increase the diagnostic error count. Compilation therefore proves that the
analysis ran; it does not prove that the program passed it. The whole-project
graph run is also stronger than an ordinary unit translation because summaries
are not currently serialized into `.xi` interfaces.

For a future theorem, “the function compiled” must be replaced by a precise
condition such as “the closed program has no region findings under complete
summaries.” A certification mode could enforce that condition without changing
the ordinary compatibility behavior of region warnings.

## Scope ownership and RAII

`Scope` already provides deterministic region ownership. Allocations belong to
the active or explicitly named scope, can move to another owner, can end early,
and are reclaimed most-recent-first when their owner is released or destroyed.
This is the arena or region form of RAII: the owner is a region rather than
necessarily one lexical C variable.

Ordinary `Scope.malloc` is sufficient for an object consisting solely of
managed memory. Reclaiming the region destroys all such storage even if no
object-specific `free` method is called. It is not sufficient by itself for a
record holding a native resource. A `Mutex`, for example, must run
`pthread_mutex_destroy` before its record is freed.

`Scope.malloc_finalized` supplies the stronger contract. Its finalizer runs
exactly once on early `Scope.free`, resize to zero, owner release or
destruction, and thread or process shutdown. It follows the allocation through
`Scope.move`, and allocations are finalized most-recent-first. This is enough
to attach non-memory resource destruction directly to region ownership.

The important distinction is that merely defining `T.free` does not register
that method as a `Scope` finalizer. Generated pointer-class cleanup calls the
selected `free` when a value participates in `Cleanup`, but ordinary region
teardown can reclaim the pointer-class allocation without invoking that
cleanup. Generated cleanup also does not recursively free fields. A universal
RAII claim therefore requires the following construction rule:

> Every object's storage is owned by a `Scope`. If reclaiming the storage is
> not the complete destruction operation, the allocation carries its proper
> finalizer, or a statically proved region-close obligation runs equivalent
> cleanup before reclamation.

Under the restricted scope of this report, attaching the finalizer is the
simpler universal rule. It avoids depending on `defer` or non-local cleanup
semantics which this research has set aside.

This rule also separates ownership from representation. Generated pointer
class conversion to `Var` preserves object identity; generated aggregate
conversion creates a Scope-owned copy. Raw pointer, reference, and object
`Var` tags borrow the address and do not acquire it. Map slots shallow-copy
their keys and values, and Map cleanup releases the map record and its backing
blocks while borrowing the stored values. These operations are compatible
with deterministic ownership, but none independently establishes ownership.
Their borrow, copy, and identity effects must be visible to the analysis.

## The interpreted realization

The compiler lowers an accepted meta function to ordinary Lisp. Direct named
calls become calls through session globals. Locals whose addresses are taken
become evaluator-owned cells read and written through typed load and store
operations; they do not become native addresses into a transient C stack
frame.

Every public evaluator entry pushes the Lisp session's `Scope`. Native
bindings reached during evaluation consequently allocate into that session
unless they explicitly select another owner. Destroying the session destroys
its Scope and all session-owned globals, lambdas, transferred functions,
prepared programs, cells, and reusable machine slots.

The automatic word machine changes execution cost and representation, but not
the source program's ownership obligations. It obtains reusable session-owned
machine slots, copies arguments into machine locals, opens frame storage above
those parameters, and returns the slot to a free list after the invocation.
The recursive evaluator and word machine are two implementations of the same
lowered Lisp behavior.

The relevant abstraction is therefore this mapping:

| Native realization | Interpreted realization |
| --- | --- |
| C stack activation | Evaluator or word-machine frame |
| Ordinary local | Evaluator binding or machine slot |
| Address-taken local | Session-owned evaluator cell |
| Active native `Scope` | Lisp session `Scope` |
| Direct source call | Lisp lambda, alias, adapter, or native binding |
| Scope-managed allocation | Session-owned allocation unless explicitly moved |
| Activation return | Frame or slot release, subject to value provenance |

The right-hand side often retains storage longer. It is not required to
reproduce every native `Scope.release` at the same instant. It must instead
preserve the abstract ownership relation: a value valid in the native graph
remains valid in the interpreter, a value invalidated in the abstract graph is
not exposed as live, and every retained resource is eventually finalized by
its interpreted owner.

## Why literal call-graph equality is too strong

The authored call relation is largely preserved: a call from one meta function
to another becomes a Lisp call to the corresponding installed definition.
The implementation call graphs nevertheless differ at the standard-library
boundary.

The compile-time environment contains several kinds of entry:

- direct native bindings;
- alternate names for an existing operation;
- Lisp implementations of an operation;
- adapters which materialize or reshape a result; and
- evaluator primitives with no ordinary source-level representation.

For example, iterator helpers adapt C out-parameters to evaluator cells,
`Map.try_next` presents an evaluator-friendly aggregate result, and some
String construction is an identity operation over the Lisp representation.
Dynamic `Func` invocation and explicit iterator destinations are also lowered
differently from native C execution.

These differences do not invalidate the equivalence argument. They show that
call-graph shape alone is insufficient. Each boundary operation needs an
abstract lifetime effect independent of its implementation:

- the owner of each fresh allocation;
- which inputs and results are borrowed;
- which values are copied, retained, stored, or transferred;
- whether an operation can end an owned lifetime;
- the provenance and lifetime of its result; and
- which exact-once finalizer, if any, follows an allocation.

An alias, Lisp shim, or native adapter is valid when its effect equals or
safely refines the native operation's effect. This is a small
ownership-effect simulation over the installed capability surface, not a
requirement that both executions use identical instructions or frames.

## Candidate theorem

Let `N(f)` be the native ownership-effect graph of a dual-form meta function
`f`, and let `I(f)` be the graph produced by its evaluator execution. Nodes
represent owners, values, and allocations. Edges represent borrowing,
retention, storage, transfer, and reclamation. Calls are labelled with their
function summaries.

Let `q` map native activations and their storage onto evaluator frames, cells,
machine slots, and the session Scope. The evaluator safely simulates the
native program when:

1. `f` and every reachable native function are region-clean under complete
   project summaries.
2. Every constructor allocates into the current abstract owner, or returns a
   canonical or borrowed value with declared provenance.
3. Every resource requiring destruction has an exact-once finalizer attached
   to its allocation or an equivalent proved close operation.
4. Every installed compile-time binding has an effect equal to or safer than
   the corresponding native operation.
5. Container and `Var` edges are classified as borrowed, copied, retained, or
   transferred rather than inferred from representation alone.
6. A returned or stored value cannot outlive its abstract owner unless it is
   moved, promoted, copied, canonicalized, or reconstructed into a longer-lived
   representation.
7. `q` never maps an allocation to a shorter-lived owner and preserves every
   retaining and finalization edge.
8. The unsafe and non-local behaviors excluded above remain unreachable.

Under these premises, any dangling reference in `I(f)` would map back to an
owner violation in `N(f)`, contradicting the region-clean premise, or to a
binding whose declared effect does not refine its native counterpart,
contradicting the binding premise. Session teardown supplies deterministic
reclamation for evaluator-owned storage. The result is lifetime safety for the
interpreted execution without independently rediscovering its borrow graph.

This is a proof sketch, not yet a formal proof. Its value is that every premise
corresponds to an existing compiler boundary or a bounded piece of missing
metadata.

## Current gaps

The present implementation falls short of certification in specific ways:

1. **Warnings do not reject.** Region findings are advisory, so successful
   compilation is not a region-safety certificate.
2. **Unit summaries are incomplete.** Ordinary compilation derives summaries
   within one unit. `x2c-graph region-escapes` is needed for holistic
   cross-unit results.
3. **Unknown calls look harmless.** An unknown callee currently receives the
   empty effect summary rather than a conservative or verified contract.
4. **Bindings have no paired ownership contract.** The compile-time API
   inventory records availability and representation, but it does not
   mechanically prove that an alias or adapter refines the native operation's
   lifetime behavior.
5. **Destructors are not universally attached.** Scope allocation guarantees
   byte reclamation, but a type's ordinary `free` or generated `cleanup` is
   not automatically a Scope finalizer.
6. **Compiler-only meta functions lack a native witness.** A definition
   removed from the runtime AST cannot inherit a proof from native region
   analysis without an analysis-only form.
7. **Result equality is weaker than lifetime equivalence.** Native and
   interpreted evaluation can return equal values while one leaks, retains a
   dangling reference, or omits native finalization. Differential result tests
   support semantic parity but do not prove ownership parity.

The current meta subset also rejects `defer` and cleanup because the evaluator
owns its values until session teardown. Within today's surface, interpreted
execution often replaces early reclamation with longer session ownership.
That is a safe coarsening for managed memory, but native-resource finalization
still requires the construction invariant.

## A path to a mechanical guarantee

The smallest useful next artifact is a lifetime-effect inventory of the
compile-time capability table. For each installed operation it would record:

| Field | Meaning |
| --- | --- |
| Native target | The operation analyzed in native execution |
| Meta implementation | Direct binding, alias, Lisp shim, or adapter |
| Result | Borrowed, fresh, canonical, copied, moved, or session-owned |
| Parameter effects | Read, stored, retained, transferred, or released |
| Owner | Current Scope, named Scope, canonical pool, or external owner |
| Finalization | None required, attached finalizer, or proved close |

This should be derived from existing compiler/type facts wherever possible.
Hand-maintained entries should be limited to real representation-changing
adapters. Certification would reject a reachable adapter whose effect is
missing or does not refine the native summary.

The holistic check would then combine:

1. the whole-project call graph from `x2c-graph`;
2. the existing region-summary fixpoint;
3. the object construction and finalizer invariant; and
4. paired lifetime effects at native/evaluator boundaries.

After the inventory establishes the actual gaps, the recommended delivery
order is:

1. Add an opt-in certification mode which combines whole-project
   `region-escapes` results with the lifetime-effect inventory. Keep ordinary
   region warnings compatible rather than turning them into unconditional
   translation errors.
2. Treat every reachable unknown call as unproved during certification instead
   of assigning it an empty effect.
3. Repair the finite set of resource-owning types the inventory finds without
   allocation-attached finalization.
4. Measure whether the certified subset is effectively identical to the
   currently accepted meta-function subset. If it is, x2c can state that its
   interpreted programs are, in practice, the programs for which native
   compilation supplies a reusable lifetime proof.

No second general-purpose borrow checker is implied. The native graph remains
the authoritative analysis. The evaluator proof checks that lowering and the
installed capability surface preserve that analysis under the coarsening map.

Before this becomes a public guarantee, probes should cover address-taken
locals, returned and stored borrows, moved allocations, canonical values,
container insertion, representation-changing adapters, early release, session
destruction, and exact-once native finalization. Negative probes should target
missing effects and deliberately mismatched adapters, not merely reproduce
every region warning.

## Research verdict

There is a substantive result here. x2c's explicit regions, whole-program
summary analysis, Scope-owned evaluator, typed `Var` boundary, and constrained
meta capability table line up unusually well. They make it plausible to prove
the interpreted subset safe by construction over the same abstract lifetime
graph used for native code.

The strongest accurate statement today is conditional: dual-form meta
functions can share the native lifetime proof when the native graph is
certified region-clean and the complete compile-time surface is certified as
an ownership-effect refinement. Establishing those two certificates, plus a
universal finalization rule for resource-owning objects, would turn the
research conclusion into a strong and comprehensible memory guarantee.
