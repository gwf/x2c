# Meta recovery: architecture and execution boundaries

> Status: obsolete
> Superseded on 2026-09-22 by the byte-storage implementation recorded in
> [meta recovery](../meta-recovery.md). This design kept a record
> wrapper, a per-allocation tracker and a runtime scalar dispatch that the
> independent review rejected; it is preserved as evidence only.

## Agreed result

Interpret code as a simulation of its compiled C/x2c behavior: value copies,
aliasing, mutation, addresses, and lifetime have the same meaning. Undefined C
behavior is not a promise of a particular interpreted result. Stronger x2c
guarantees come from the shared compiler analysis, not a second interpreter
policy. Architecture is an acceptance criterion, not post-implementation polish.

- The compiler Type/Sym machinery owns type identity and derived layout.
- Existing compiler region/borrow/effect analysis owns the lifetime facts it
  proves; missing facts are extended there, not presumed already implemented.
- Scope owns allocation and reclamation; Context owns established exports.
- Existing Var and protocol conformance own representation and cleanup rules.
- Ordinary and inline local structs work without a per-type runtime API.
- A struct from a real system header, filled synchronously by a native API,
  is a primary acceptance case, not an optional foreign-type feature.
- Reference-like objects preserve identity. Struct values copy; pointer fields
  remain pointers and do not cause implicit deep copies.
- Marking a type does not advertise every method. Native binding inventories
  are derived from marked declarations, never a second handwritten math list.
- User native extension building/loading is the final campaign stage. Current
  internal use accepts rebuilding the compiler with new native bindings.

## Source baseline and evidence

Inspected working tree: codex/meta-values-types at ab849674, including local
recovery edits. Source traces below establish current structure, not a passed
execution gate for the proposed replacement. No implementation changed during
this planning pass. Existing generated bootstrap deltas are not proof of the
current authored tree.

Relevant owners:

| Fact or operation | Existing owner |
| --- | --- |
| Native scalar identity and Var conversion selection | src/type.x: scalartypes, Type.scalar, scalar_tag, var_numeric_extractor |
| Typedef resolution and ordered aggregate members | src/compiler.x: Sym.resolve_key, normalize_declared_type, field_order |
| System-header declaration discovery | src/frontend.x: _preprocess_input; src/parse.x: _publish_aggregate_type |
| Native allocation size/owner/finalizer | lib/scope.x: ScopeMetadata, Scope.owner, move, destroy |
| Value export | lib/context.x: export_scope, export_nested, move_allocation |
| Actual interpreted calls | lib/lisp.x: _call_lambda_slots, _apply_lambda, apply_values |
| Source-function lowering/installation | src/comptime.x: lower_comptime, install_comptime |
| Native lifetime summaries | src/regions.x: Fact, Region, region_escapes |
| Whole-project summary propagation | tools/x2c-graph/x2c-graph.x: region-escapes |
| Iterator adoption and callback interfaces | lib/protocols.x, lib/iter.x, lib/lisp.x: _lisp_callback |

## 1. Type and storage: one owner, minimal bridge

### Existing facts and actual gap

Type.scalartypes maps exact C spellings to Var tags, extractors, and update
helpers. Var.numeric_info is a different, legitimate projection: Var numeric
families and promotion widths. It does not supply native alignment or raw
storage operations. In particular, Var's i48/u48 families are not native C
field types. Do not infer C layout from Var payload width.

Derive native scalar size/alignment and typed read/write operations from the
existing exact C-type ledger. If generating multiple projections requires
lifting that ledger into shared compile-time source, move the enumeration;
do not copy it. Generate sizeof/alignof and typed C locals from the row's type,
using existing conversion/extraction operations. No manually maintained scalar
aliases, size constants, second tag switch, or new public type IDs.
Concretely, the single moved ledger generates both today's Type lookup and
private storage-operation records containing tag, sizeof(T), alignof(T), and
typed load/store functions. Field descriptors reference those generated
operations; no independently maintained ordinal/tag mapping is allowed.
Var.numeric_info remains conversion/promotion metadata. i48/u48 never acquire
native storage rows because no exact C-type row names them.

An exact scalar's native bytes and its declared `Var` value family are distinct
facts. In particular, `Symbol` has `unsigned long` storage but crosses the
evaluator as `<symbol>`; resolving the typedef must not erase that conformance.
The existing symbol payload operations provide that reversible crossing. An
arbitrary scalar `protocol Var(T)` currently supplies only its forward `T.var`
converter, not a generic inverse/native-payload contract. Supporting an
addressed value whose protocol tag differs from its exact numeric storage tag
therefore remains an unresolved boundary; until that contract is designed, the
layout query must decline it rather than silently store the protocol value as
the resolved numeric family.

The Type/Sym-owned aggregate query resolves the canonical type and member order
and produces an immutable derived layout. Cache it only under canonical type
identity and the relevant compilation configuration. Keep meta adoption
membership distinct from the cache; cache presence does not grant availability.
Move this query out of macros.x, whose job is declaration advertisement.

The evaluator bridge needs only typed backing storage and field/address views.
It does not own a second type system, allocation list, execution stack, or
escape scanner. Existing raw Var pointers lack complete aggregate type facts;
Lisp cells hold one Var, not arbitrary C bytes. Therefore a small typed carrier
is justified, but its exact tag count is an implementation detail, not a new
protocol or public subsystem. An address view identifies its backing plus a
field/offset; it does not acquire independent ownership.

Keep assignment as a copy into the destination's existing bytes. Do not replace
the destination object and invalidate field aliases. Native adapters use typed
C calls and locals through the existing Func generator, not handwritten ABI
dispatch. The present computed-layout boundary needs a single per-type native
layout agreement check before passing bytes to native code; repeated assertions
per adapter are unnecessary. This is not authorization for an ABI test project.

### System headers

The normal collector deliberately does not fully read unresolved system
headers. The existing cpp-symbols/live-symbols frontend path preprocesses and
shallow-parses actual host headers and, where that parsing succeeds, publishes
aggregate bodies/member order to Sym while retaining original source for full
parsing. Reuse that path; do not copy
system record definitions or teach the evaluator OS-specific layouts.

Approved first delivery (Gary, 2026-09-22) uses existing `--cpp-symbols` discovery
when a required header body is otherwise unavailable. Automatic discovery is
deferred; preprocessing happens before full meta parsing.
Do not silently select a different header or configuration. Verify that include
paths, defines, toolchain, and layout-affecting flags match native compilation.
The system-header acceptance fixture must exercise the approved `--cpp-symbols`
invocation and matching native compilation configuration.

Current member facts do not establish packed/aligned records, unions, bitfields,
anonymous members, array/flexible-array members, or all pointer families.
These are known coverage gaps, not approved exclusions. Select real OS-library
acceptance cases first and expose any incompatible field shape before scoping
it out. Scalar/nested-record probes alone do not prove the primary use case.

## 2. Function calls and returns

Agreed behavior: a returned struct value reaches caller-owned storage before
callee automatic storage is reclaimed. No hidden result-slot calling convention
is required for first delivery; ordinary return plus a copy is sufficient in
principle. A future elision is not part of this recovery.

Current _call_lambda_slots already has a Scope named Lisp frame. It currently
owns bindings, not all automatic record storage. Public Lisp.eval/apply now open
the recovery arena only at the outer entry; nested calls reuse it. Thus current
code does not implement per-source-function automatic-storage reclamation.

Selected integration shape (source-backed proposal; not yet executable proof):

1. Evaluate call arguments while the caller is live.
2. Distinguish a lowered source-function activation from synthetic Lisp lambdas
   used to implement expressions/control flow. Do not turn every lambda into
   a new C function lifetime.
3. Mark the installed source-function Lambda explicitly at install_comptime,
   including cache/shared-definition installation. Use its existing detached
   Lisp frame Scope for automatic locals and address-taken cells, not a second
   arena. Synthetic lambdas borrow that automatic owner, not their own temporary
   binding-map frame.
4. Evaluate its body. Preserve caller-owned objects passed by reference.
5. Copy a by-value aggregate result into caller automatic-result storage while
   the callee remains alive. Reference-like results retain native ownership
   semantics; do not clone them because they cross a call.
6. Release callee automatic storage on normal return and Error unwind. If copy
   or conversion raises, cleanup must still run in the right order.

The narrow plumbing candidate is one borrowed automatic-owner pointer on the
existing Lisp session, saved/restored by C-stack locals at marked calls. This
is call context, not an allocation registry or second execution stack. Existing
lisp_active selects the session for lowered storage primitives. Automatic-cell
and record operations allocate explicitly into that owner; they do not redirect
ordinary Func calls. Unmarked ordinary Lisp uses its existing ambient owner.
Result export temporarily pushes the previous automatic owner with Scope.push
(the session Scope at the outermost call), calls Context.export_scope while the
callee frame is live, then pops the destination before restoring the saved
automatic_owner pointer and destroying the callee frame. Merely changing the
borrowed Lisp pointer is not enough: Context.export_scope reads Scope.top().
The destination is selected only while copying the returned value, not during
body execution. Cleanup restores it before the callee frame is destroyed.
Existing Context.export_scope performs the
representation dispatch while both scopes are live. No hidden source argument
or Func ABI change is proposed.

Conceptual call order, using the existing frame (not new API spelling):

```text
evaluate arguments in caller
enter existing _call_lambda_slots; create existing bindings/frame Scope
if this is an installed source function:
    save session.automatic_owner; point it at this frame
    defer restore pointer before frame teardown
evaluate body without pushing frame as native ambient Scope
if source function:
    Scope.push(saved caller automatic owner, or outer session owner)
    export returned value from still-live frame using Context
    Scope.pop() even if export raises
existing deferred frame teardown
```

This private pointer is borrowed, not retained in an escaping callback or object.
The existing Lisp session is serialized; ordinary reentrant public entries save,
clear, and restore it. No concurrent sharing guarantee is added. Storage helpers
must either require active lowered execution or accept an explicit owner in their
test harness; direct old MetaExecution tests do not justify retaining that API.

Public Lisp entry must save/restore or clear this private pointer consistently;
internal callbacks already use _call_lambda_slots and can preserve the current
source activation. Verify reentrant public evaluation independently: do not
silently change the documented session ownership of ordinary Lisp.eval/apply.
The source-frame marker must also prevent AUTO-machine preparation initially,
because machine frames/tail retargeting do not implement these Scope boundaries.
This is an execution-path restriction, not a language restriction; optimization
can be restored only after its existing frame lifecycle implements the same rule.
Disable AUTO within an active source activation as well until synthetic-machine
calls are shown to preserve the same boundary. Retain ordinary Lisp AUTO outside
that context. Measure/report the performance restriction; do not hide it.

Materialize by-value record parameters in the callee's automatic frame rather
than keeping the existing caller-side clone plus callee cell. Generated copies
for assignment/return must retain their distinct semantic roles. Scope teardown
is deferred at the call boundary; conversion/export failures must also unwind.
Specifically, before binding/reading the body, copy each aggregate parameter
from the borrowed argument array into fresh callee-owned bytes. Do not alias
the caller's aggregate through that array. Scalar/reference parameters retain
their existing behavior.

Every aggregate return expression must produce a value snapshot, including
when its operand names a caller/session-owned aggregate. Retain the lowerer's
typed return-value copy into callee automatic storage, then export that owned
snapshot into caller storage. Generic Context export's "already outside source"
identity shortcut is not a substitute for this C value copy. Removing an extra
copy can be considered later; no result-slot optimization is required now.

Important established separation: C automatic storage dies with its activation;
ordinary Scope-allocated heap objects follow the explicitly active source Scope,
not necessarily the function return. Automatically pushing the local-record
Scope for every native allocation can shorten heap lifetime and manufacture a
need for extra export barriers. Do not impose that behavior on ordinary Lisp or
native Array/Map constructors without establishing compiled-code equivalence.

## 3. Persistent values and shared lifetime analysis

REPL bindings live in session storage; source automatic locals do not. Assignment
to a persistent struct copies into its existing storage. A pointer to an expired
local is not repaired by copying its containing record or keeping its box alive.
Persistent-global export targets the session explicitly; function-return export
targets the caller's automatic owner. Do not reuse a helper that conflates these
two destinations. Existing C.gwrite/C.mgwrite identify the persistent operation.

Array.setindex/push and Map.setindex are shallow stores; they preserve receiver
identity and do not automatically transfer ownership of inserted referents.
Context export can move source-owned object graphs while preserving identity,
but exporting the function's final result misses writes to pre-existing objects.

Do not solve that omission with a new interpreter-only write barrier. Preserve
the source program's actual allocation owners: ordinary Array/Map construction
keeps the ambient native Scope, rather than the automatic-local frame. Existing
container writes then keep the same receiver/referent semantics as native code.
This removes the broad promotion problem created by the rejected allocation
override. Explicit source-owned shorter regions still need the same explicit
export/transfer or lifetime diagnostic as compiled code.

Aggregate-to-Var boxing is a separate value conversion: a copied aggregate must
not remain merely a handle to automatic-local bytes when the native conversion
creates an owned copy. Use the existing Var aggregate conversion contract for
that crossing; pointer fields remain borrowed. Closures similarly need the
source capture semantics, not an eager deep export of every captured Var.
This exact conversion/capture integration remains a bounded verification item.

The native region analysis already has binding/owner/points-to facts, sink
classification, and interprocedural summaries. It is currently warning-based
and explicitly incomplete for raw stores, pointer arithmetic, callbacks, and
automatic/interior references. Unknown calls are not proof of safe effects.
Extend the native owner where this feature needs additional facts; do not build
an interpreter checker or replace the side tracker with an allocator scan.

Meta code can execute during parsing, before the ordinary transform-time region
warning pass. Any required pre-execution check must reuse the typed native
analysis before installation, including necessary callee effects. Keep missing
effects distinct from proved invalid lifetime. Do not turn a warning pass into
blanket certification or refuse all unknown calls without explicit review.
Cross-unit facts belong to existing declaration/interface summaries; whole-
project graph analysis remains useful evidence, not a mandatory new build stage.

The plan must distinguish three outcomes: behavior valid in C/x2c, a lifetime
violation established by shared analysis, and insufficient analysis coverage.
The last is an engineering gap or proposed support limit, not a new runtime
escape policy. Compile-time-only code still needs the same typed analysis input;
do not create a second analysis because native emission is omitted.

## 4. Protocols and iterators

Current Iter(T) requires T.iter(T, Iter dest). Do not replace it with the earlier
hypothetical associated-value/try_next protocol while implementing meta.
Existing typedef adoption can forward to an ancestor implementation; Var `as`
adoption is representation forwarding, not a second Iter adoption mechanism.

Internal case: lower ordinary protocol-selected iteration through its existing
iterator construction and advancement contract. Today direct List/Array/Map
cursor paths and general Iter lowering differ in binding coverage. Fill the
existing operation's binding/lowering gap, not a second foreach engine.

User case: meta-authored map/filter/scan callbacks can use _lisp_callback and
Func-backed iterator stages. They do not inherently require native extensions.
The existing IterNextFn is a native status/output-pointer callback, whereas an
interpreted callable is represented by Func/Lambda. A genuinely new pull kernel
needs a concrete reusable bridge or ordinary interpreted lowering; current
absence is not proof that dynamic loading is the only solution. Do not promise
custom generators merely because composition works. This is a bounded remaining
engineering question, not authorization for a new iterator protocol.

Trace iterator destination storage, source, callback, and captured state together.
Local caller-provided Iter storage must not be passed to Scope.owner as though
it were a Scope allocation. Returning an address to a native automatic iterator
is invalid; returning a Scope-allocated iterator follows its existing lifetime
and borrowed-source contracts. Cleanup conformance and resource finalization
must be applied exactly as in compiled code, not inferred from the word meta.

## 5. Native extension loading: last stage

Keep current compiler-linked bindings and declaration-generated adapters.
User-authored interpretable meta bodies need no compiler rebuild; newly linked
native implementations do. This boundary is accepted for current internal use.

Final campaign stage: build a host-loadable module containing user native code,
generated typed adapters, and registration; explicitly load it for translation,
build, or REPL use. Reuse compiler types, Func conversion, normal build tooling,
and the same registration path as built-in natives. No libffi or handwritten
calling-convention engine is required by this typed-adapter proposal.
CLI spelling, module compatibility/lifetime, and runtime sharing are deferred.
Do not build plugin scaffolding during the current stages.

## Current-diff disposition

| Keep subject to verification | Consolidate | Remove |
| --- | --- | --- |
| Meta declaration parsing and scalar globals | Layout query into Type/Sym | Timespec-specific bridge and APIs |
| Declaration-derived native binding discovery | Scalar storage projections from existing C-type ledger | Duplicate scalar aliases/dispatch inventories |
| Ordinary/inline record lowering | Typed storage and address views into existing value/call owners | MetaAllocation and allocation/record chains |
| In-place assignment and typed native call adapters | Invocation-local bytes into source call lifetime | Fixed meta execution stack and redundant ownership flag |
| Behavioral C/interpreter parity probes | REPL persistence into existing transaction/ownership paths | Blanket arena redirection of ordinary Lisp/native allocation |

Do not hand-edit bootstrap artifacts. Preserve unrelated dirty changes. Existing
tests built on hand-assembled private descriptors need replacement with generated
descriptor coverage; do not loosen runtime checks to satisfy invented test data.

## Execution sequence after review

1. Close the call-frame, heap-owner, and iterator callback engineering items;
   use the approved explicit `--cpp-symbols` header-discovery policy.
   Record exact owners and call order, not a menu for an implementing agent.
2. Consolidate type/layout/scalar projections and remove duplicate inventories.
3. Replace the rejected storage subsystem with the minimal automatic-storage
   bridge integrated at the settled call boundary. Preserve native heap owners.
4. Integrate shared lifetime facts and explicit persistence/cleanup behavior;
   verify protocol and iterator paths without broad unrelated API changes.
5. Exercise real system-header/native-by-reference code alongside inline/nested
   records, alias-preserving assignment, returns, recursion, and exceptional exit.
6. Independently review authored diff for duplicate owners and changed semantics;
   fix findings before generating artifacts and running the exact-tree gate.
7. Present tested local diff for user review; no push is authorized here.
8. Native extension build/load remains the separately reviewed final stage.

## Behavioral evidence required

- Same source-level results for native and interpreted code; no private layout
  reimplementation inside the expected-result oracle.
- Existing field address observes whole-record assignment; value copies do not
  alias unless their fields deliberately contain pointers.
- Returned aggregate survives callee teardown; recursive/sibling calls and
  error paths reclaim automatic storage, measured at the correct boundary.
- Scope-heap allocations retain the same owner as native execution, including
  writes through persistent Array/Map aliases; no invented deep copy.
- Actual system-header struct written by a synchronous native API, with the
  same header/configuration on discovery and compilation paths.
- Internal adoption, user callback composition, iterator return/source/capture
  lifetimes, and any approved custom pull mechanism are separate checks.
- Ordinary Lisp behavior and REPL transaction/rollback remain compatible.
- Full gate only after the authored design and implementation are reviewed.

## Plan review

Independent type/architecture review was completed and its four actionable
findings incorporated: explicit Scope.push/pop at result export, fresh aggregate
parameter/return copies, qualified lifetime-analysis coverage, and concrete
single-ledger scalar projections. The ownership reviewer separately traced the
borrowed automatic-owner/call-frame candidate against existing source. Neither
review ran an implementation prototype; feasibility is source-backed, not a
claim that the proposed mechanism has passed executable validation.

Canonical parser/Type/Sym facts establish identity and member order, not every
native layout. Generated scalar operations must derive from exact C types, not
Var encoding widths. A native crossing agreement check prevents wrong byte
interpretation; repeating it per adapter does not add value. No new AST-origin
validator, allocation registry, interpreter escape checker, or ABI survey is
proposed.

Existing Scope, Context, call frames, Func adapters, protocol selection, and
native region summaries are the owners to reuse. A small typed byte carrier is
necessary because a Var cell is not aggregate storage; it must remain only a
representation bridge. New lasting helpers require a demonstrated missing
operation at one of those owners, not convenience for a parallel subsystem.

Negative probes are justified only for actual unsupported public boundaries or
demonstrated lifetime/native-crossing errors. No generic demand for more checks
or stronger diagnostics authorizes scope expansion. The remaining unresolved
items above prevent describing this draft as executable without further review.
