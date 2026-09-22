# Meta authoring, literal results, and API coverage

> Status: active
> Gary approved execution and all five recommended decisions on 2026-09-20.
> The initial implementation shipped in 8ebb323d. Value aliases and further
> AD source templates shipped through 8c2a8054; x2c-first examples followed in
> 95e73d18. Capture-call repairs and remaining API/representation work extend
> that baseline. The exhaustive value-operation continuation now accounts for
> all 483 signatures. The current tree has 385 rows with bindings and behavioral
> evidence for every bound row. Implemented behavior and open follow-ons are
> recorded below. The 2026-09-21 addendum separates excluded native contracts,
> adapter work and defects from work delegated to generalized `meta`
> declarations and lifetime certification.


## Outcome and priorities

Campaign sequencing update (2026-09-22): user-provided native extension build
and dynamic loading belong to the final campaign stage, not the current
record/type/lifetime recovery. Compiler-linked bindings with compiler rebuilds
are sufficient for current internal use. The workflow and deferred decisions
are recorded in [meta recovery](archive/meta-recovery.md#campaign-sequencing-decision-native-extensions-last).

Make ordinary macro and meta programming possible using readable x2c source.
Meta functions compute values; macros emit code and turn values into code.
Code can itself be a List value passed between meta functions.

Two equal top priorities:

1. Call source-code templates from meta functions, starting with the generated
   gradient function in `lib/autodiff.xmacro`'s `ad_reverse_function`.
2. Insert every representable literal result of compile-time evaluation with
   the correct type and value, starting with native scalar literals and strings.

Explicit dollar-prefixed meta calls connect these priorities: macro authors
must be able to call a meta helper with captured arguments without writing a
Lisp wrapper. API coverage, lowering correctness, and documentation complete
this round rather than remaining a list of unexplained exceptions.

This plan builds on [meta-functions.md](archive/meta-functions.md) and
[comptime-x2c-generalization.md](archive/comptime-x2c-generalization.md). Their historical
implementation limits are evidence, not permanent restrictions. Do not redo
the generated built-in Lisp migration that has already landed. The separate
[generated Lisp reproducibility plan](generated-lisp-reproducibility.md) is
not an additional gate for this effort.

## Planning evidence (historical)

For current operation coverage, use the [API report](../docs/src/guide/meta-api-coverage.md).
The counts and defects below record the pre-implementation baseline.

Baseline: development commit `f3aa43a5`, with a fresh safe bootstrap rebuild.
The following were refreshed against that compiler during planning:

- A meta function returns a canonical deferred `macro-invoke` List for a Unit
  template. Normal binding expands it into a function returning 42; the native
  program prints 42. This establishes reuse of the existing expansion path,
  not the proposed convenient call syntax or the full AD conversion.
- A meta function initializes `unsigned char values[1] = {n}` and returns
  `values[0]`. Explicit compile-time evaluation with 257 prints 257; a native
  call with 257 prints 1. Element initialization loses the C conversion.
- The draft inventory finds 483 exported callables across the six requested
  core types. It matches 94 to bindings and finds 389 without matches. This is
  a discovery result, not proof that 94 operations work or 389 cannot work.

| Type | Exported candidates | Binding matches | No binding match |
| --- | ---: | ---: | ---: |
| String | 89 | 28 | 61 |
| List | 95 | 21 | 74 |
| Array | 61 | 17 | 44 |
| Map | 38 | 12 | 26 |
| Symbol | 14 | 2 | 12 |
| Var | 186 | 14 | 172 |

Earlier focused probes and source inspection establish leads to recheck in
implementation: floating results can compute successfully but fail explicit
insertion; normal-call folding has a narrower result path; suffixed numeric
literals fail in some lowering paths; Array.map, List.foldl and general iterator
objects lack equivalent compile-time exposure. Do not promote binding searches
or old probe results into complete behavioral coverage.

The source owners are `src/comptime.x` for lowering and folding,
`src/macros.x` for sessions, captures, invocation and result insertion,
`src/expressions.x` for expression parsing, and `src/parse.x` for ordinary
syntax binding. `lib/meta.x` owns public compiler helpers. Numeric token and
literal knowledge already lives in `lib/scan.x` and `src/type.x`.

## Requested language direction

- `$helper(args)` explicitly requests compile-time execution of a meta
  function. It applies in ordinary source and macro bodies.
- `helper(args)` remains an ordinary call, with optional folding where legal.
  Inside an executing meta function it calls within that evaluation normally.
- Resolvable arguments include values computed from other resolvable values
  and meta calls. They are not limited to textually literal arguments.
- In a macro, passing a captured expression to a code-processing helper passes
  that expression's code value. It does not execute the future program's
  runtime expression.
- A source template should describe generated declarations and statements
  directly. Meta code computes the pieces instead of assembling every node.
- Keep existing Lisp authoring and canonical hand-constructed AST Lists legal.
  Lisp remains available for deeper language work.

## Approved decisions

These decisions were approved with the execution request.

1. **Expansion timing:** a template call in meta returns a deferred invocation.
   It expands when inserted into a code position through the ordinary binder.
   Obtaining an already expanded AST for further inspection is a separate
   capability, not silently implied by the first implementation.
2. **Name collisions:** preserve visible macro precedence for dollar calls;
   otherwise resolve a meta function using ordinary binding and argument typing.
   Do not silently change existing macros when a function has the same name.
3. **Template construction context:** initially support Unit and Statement
   templates used as expressions inside meta functions. Their arguments are
   computed values. Preserve existing Expression macro expansion, including
   inside meta bodies; never select interpretation from the destination's List
   type. Extend other result kinds only after a concrete use needs them.
4. **AD names:** let the source template own its fresh local/label names and
   pass those Name captures to fragment-producing meta helpers during expansion.
   This avoids adding a new public fresh-name allocator in the initial change.
   If this arrangement cannot express the real generator cleanly, revisit it
   before introducing an alternative allocator.
5. **Captured code versus values:** direct forwarding of a macro hole supplies
   its captured code; ordinary meta argument expressions supply computed values.
   Do not infer that distinction merely from a List parameter, because Lists can
   be data or code. Reuse explicit evaluation or value-to-code conversion at a
   crossing; settle the exact user-facing operation before implementing one.

## Work 1: source templates and explicit meta calls

Owners: expression parsing, comptime lowering, macro capture and expansion.
Deliver this as connected compiler work, then migrate AD on top of it.

### Explicit calls and resolvable inputs

Resolve the dollar call using the decision above. Reuse the current evaluator
and declared argument conversions. Outside meta execution, resolve inputs and
execute explicitly; inside meta, evaluate against current parameters and locals,
not prematurely while parsing the function definition. Inside executing meta,
the call returns its computed value unchanged. Insert that value as program
code only at the code boundary, never automatically after each nested call.

Reuse the compiler's existing constant/cache handling to define resolvability.
A cached value is usable only when its type, lifetime, scope and dependencies
remain valid. Cache presence alone is not the rule. Do not add another cache or
assume that every computation is pure. Preserve evaluation order and existing
budget/error behavior. Explicit evaluation must report inability to execute;
optional folding may retain the runtime call without changing program behavior.

Acceptance example: the shape macro invokes `$shape_names($value)` using
C-style arguments and inserts its returned code, without a Lisp call wrapper.
Check a literal argument, a computed argument, nested meta calls, a valid cached
value, and an expression capture that refers to a future runtime variable.
The direct captured-hole argument must arrive as code, even if the future
runtime expression itself has List type. Separately exercise an ordinary
computed List argument so data and code are not inferred from the same type.

### Template calls as values

Parse builder arguments as ordinary expressions evaluated during meta execution.
For example, a local holding computed parameters supplies that List, rather
than capturing the identifier naming the local. Use the template's existing
hole kinds to normalize Name, Type, Param, expression and statement values.
Reuse capture rows and canonical deferred invocation nodes; retain the selected
macro definition by the existing nested-invocation mechanism.

Expansion must reuse normal substitution, binding, placement, recursion limits,
source positions, fresh names and semantic transactions. Propagate existing
compiler-only meta classification. Do not call the syntax binder early just to
make the constructor look like immediate expansion.

Resolve sequence arguments with the real gradient signature and body. Current
sequence-hole restrictions must not force users to build a manual function AST
again. Prefer computed List arguments normalized into existing splice captures;
change grammar only where this concrete case requires it.

Acceptance: a meta function computes a value and returns a template invocation
that generates a native function; then exercise computed parameters, a statement
sequence and nested invocation. Existing expression macros must behave exactly
as before. No destination-type-dependent behavior.

### Convert the gradient generator

Move the function declaration, modifiers, parameter list and fixed body structure
out of hand-built AST output into a source template. Keep derivative analysis in
meta helpers and use Match for input structure. Preserve storage, linkage,
return type, source parameters, added gradient parameters and emission order.

Splice generated declarations and statements into the intended function scope;
extra blocks must not hide locals from later fragments. Shared AD scratch names
and labels must have identical binding identities in the scaffold and fragments.
Names allocated during deferred expansion cannot be guessed in earlier meta
computation by writing the same text.

Verify native gradient results with the existing AD examples, plus the meaningful
boundary cases for modified parameters, modifiers, shared locals and labels.
Inspect generated code for those properties. Continue replacing fixed output
AST construction in adjacent AD helpers where source templates make it clearer.
Do not impose a zero-AST-construction quota or rewrite unrelated compiler code.

## Work 2: literal results and scalar correctness

Owners: shared typed value-to-code conversion, comptime lowering, numeric types.
This is the other top priority and can progress independently of template design.

Unify the conversion used by explicit evaluation and eligible normal-call folding.
Preserve declared type, signedness, width, floating precision and computed string
contents. Start with the native scalar types that have literal representations,
including character, narrow/wide integer and floating results. Keep current
computed strings and Symbols working. Cover negative values, boundaries,
escaping and floating round trips rather than only small positive integers.
Special floating values need the existing legal representation or an explicit
record of the remaining gap; do not silently change their values.

Distinguish three questions in implementation and documentation: can the evaluator
compute/pass a value, can explicit evaluation insert it, and may an ordinary call
be folded? A failure in one is not proof of a restriction in the other two.

Containers remain in scope for design, not an implicit promise of arbitrary heap
serialization. Inventory existing literal constructors for List, Array, Map and
boxed values. Specify element typing, ownership, mutability, identity/sharing and
lifetime before materializing each representation. Implement representable cases
through ordinary constructors/cache ownership; record genuinely unresolved cases
with a reason and a bounded follow-on. Do not turn a pointer value into an
address embedded in generated code.

Repair numeric literal lowering by reusing scanner and type-owner knowledge.
Keep token recognition, type selection and value conversion distinct. General
String number conversion need not accept source-language suffixes. Check decimal
and hexadecimal integers, their suffixes, floating suffixes and ranges against
the normal compiled path; avoid another partial scanner.

Repair C-style array element initialization to apply the declared element
conversion. The 257-to-unsigned-char reproduction must give 1 in both paths.
Check relevant signed/unsigned and floating element conversions using existing
comptime differential fixtures. Explain storage accurately: native C storage at
runtime; dynamic Array values in mutable evaluator cells during compilation,
not stack allocation through alloca.

## Work 3: reproducible API coverage and gap closure

Turn the draft audit into an optional repository tool and readable report.
Use the existing source parser and authoritative declarations to enumerate every
public overload of String, List, Array, Map, Symbol and Var. Separate advanced
exported internals from documented user operations without hiding either set.
Include generated declarations and all session binding layers. Cross-check the
denominator against compiler symbols; report discrepancies rather than silently
dropping entries. Discover dependencies from actual session loading instead of
assuming one binding file is the whole environment.

For every operation record its signature and source, binding provenance,
compile-time call shape, behavioral evidence and explanation. Use distinct
states: verified works; reproduced failure; binding found but unverified;
no binding found. Classify the cause separately: simple omission, callback
adapter, pointer/output parameter, ownership/resource boundary, alternate syntax,
or unknown. Missing evidence is not "won't work." Report the full lists.

Run safe representative calls for overloads and edge semantics. Keep unsafe or
resource-dependent operations explicitly untested until an inert case is defined.
Do not infer a historical rationale where none is documented. The report should
explain what each missing capability would actually require.

Then close coherent groups, starting with String.strip and Map.keys candidates.
Confirm whether they are still missing in the implementation baseline. For
Array.map and List.foldl, reuse interpreted callback invocation and preserve
empty-input, seed, order and void behavior. Native Func argument machinery is
not automatically a valid bridge to an interpreted callable.

General Iter support uses `Iter.new` for session-`Scope` storage and private
one-less-argument producer bindings. It preserves native lazy producers,
callback state and source mutation semantics while leaving the allocation-free
caller-storage APIs intact. The callback bridge uses the evaluator's internal
application path so one public entry retains one call budget. Explicit native
storage remains unrepresented and is refused. True-void transport carries
absent iterator results and no-seed folds.

Correct the guide inventory: List.car, List.cdr and Var.cons were missed by a
single-layer scan; an internal Var_func helper is not evidence of a public
Var.func operation. Refresh all counts when the tool runs on the final tree.
The audit is not a new recurring gate or exhaustive generated test suite.

## Work 4: documentation and practical examples

Update the guide and reference with each delivered semantic change, then perform
a connected prose pass. Remove anthropomorphism, repetitive AI phrasing and
unnecessary uses of "spelling." Say code when discussing generated program code;
reserve syntax for grammar. Explain when `meta` is a keyword rather than framing
it as "where to write meta."

Include ordinary C-style calls to meta_whole and meta_label, explicit dollar
calls, the shape helper macro, the source-template gradient pattern, and poly
converted to Func for dynamic runtime dispatch. Say plainly that Func dispatches
the compiled implementation. The runtime evaluator can apply an interpreted
callable to values, but automatic runtime selection/export of every meta body's
interpreted version is not implemented by those Func examples.

Explain current support separately from goals, particularly literal insertion,
containers, arrays and iterators. Link the complete API report and reasons.
Explain generated built-in Lisp provenance and residual support code; do not
mistake generated Lisp for unconverted hand-authored algorithms. Revisit dummy
forward-declaration scaffolding only if the new authoring path makes it removable;
it is not independently approved compiler work.

## Dispatch, validation and delivery

1. The five language choices are approved. Start literal/scalar correctness and the
   API inventory independently; coordinate shared comptime/macro owners.
2. Implement explicit calls and template construction coherently. Land that
   dependency before migrating AD; preserve a working bootstrap transition.
3. Convert AD and repair coherent API groups using the resulting audit.
4. Finish the connected documentation rewrite and refresh the full report.

The requested startup investigation found an embedded evaluator, a lazily
prepared process parent for ordinary serial translation, and separate unit
sessions that reuse it. Parallel workers inherit the prepared parent through
fork; later calls do not reload the libraries. A new compiler process prepares
its own parent. Use the source owners above to document the exact loading order
and first execution; this finding does not authorize redesigning initialization.

Use existing comptime-lowering, meta-differential, macro and AD fixtures/examples
for focused verification. Add only cases that distinguish the behavior being
changed: literal type/value preservation, array conversion, capture semantics,
macro compatibility, scope and hygiene, and callback edge semantics. A binding
name search is not behavioral validation. Keep full failures in debug logs.

For each implementation batch, review and fix the authored diff for reuse,
deletion, trusted facts and idiomatic x2c before publication validation. Integrate
current origin/dev and review generated changes. Use the existing
`tools/gate-state.py ensure agent-pr-check` for code changes, or `doc-check` for
an independently delivered documentation-only change, on the final tree.
Delivery follows root AGENTS.md; no additional recurring gate or build sequence.

Completion means the top-priority examples run without hand-built invocation
rows or Lisp wrappers, scalar literals preserve their types and values, the
array mismatch is fixed, every requested API appears in a reproducible inventory,
and remaining container/iterator limits have explicit reasons and follow-ons.
Do not call the broad all-value-types goal complete while those limits remain.

## Implemented behavior and bounded follow-ons

The implementation adds explicit C-style dollar calls, preserves macro-name
precedence, forwards exact captured holes as code, and evaluates other arguments
as values. Unit and Statement template calls inside meta construct deferred
invocations. Parameter and statement sequences can be computed through explicit
meta slots, without adding ambiguous nonfinal sequence parameters.

The capture-call follow-on uses the same source registration as Lisp evaluation,
so complete captures retain source text and caller-relative embedded paths.
Direct typed holes, including Function captures, keep their declared kind.
Declaration lookahead and existing macro slots now admit explicit meta results
in type and generated-name positions. The `meta-capture-calls` regression covers
these paths, imported definition-relative paths, forwarding and decorator body
splicing; the formerly Lisp-only guide examples now use x2c calls.

The reverse-gradient generator now returns a source template. That template
owns fresh tape, accumulator, exit-code and label bindings, which it passes to
fragment helpers during expansion. The source function's specifiers and computed
parameters are retained. Existing AD and checkpointing examples, plus a static
inline function using the old scratch names, exercise the resulting native code.

Scalar conversion covers integer families, floating families, strings, Symbols,
immutable Lists and boxed representable values. Numeric lowering uses the existing
typed literal owner. C-style arrays convert elements to their declared type.
String.strip, Array.map, List.cons and Symbol.len filled the first binding gaps.
The next delivered batch added 19 selector, rendering, kind and comparison
bindings, retaining the documented nil-versus-void limits. That batch did not
complete the API surface.
The exhaustive continuation binds the remaining ordinary operations over
represented scalar, String, Symbol, List, Array, Map and Var values, including
the pure optional-module operations, without importing those optional source
APIs into the implicit prelude. The compound-selector continuation adds the 44
remaining List and Var selector bindings while leaving their source declarations
in the optional `list-selectors.x` module. Status-cell adapters then add nine
operations with unchanged-on-failure output contracts; direct bindings add
`Array.heap_pop`, `Map.get_hashed`, `Var.clone_wide`, `Var.getindex` and
`Var.null`. The integrated inventory has 385 signature rows with bindings and
98 without bindings. Its fixed native/meta comparisons leave no bound row
unverified: 379 rows have a verified example and 9 retain a reproduced
limitation, including 3 rows without bindings. Every binding-absent row has an
explicit owner, contract group, disposition and next action. No binding-absent
row remains classified as implementable with current values. The optional
inventory records every signature and distinguishes observed behavior from
binding presence and absence.

One representation follow-on remains explicit rather than being presented as
completed support:

- Explicit Array/Map result insertion now constructs a fresh Scope-owned root
  through ordinary literal constructors, preserving types, Array order and Map
  key equality. Only immutable representable descendants are accepted, including
  immutable Lists; a boxed Var may hold the root. Typedef aliases retain their
  value representation, and scalar boxing retains the source numeric tag.
  Empty braced returns use the ordinary initializer lowering. Ordinary mutable-return calls
  stay at runtime. Nested mutable descendants, sharing and cycles remain refused
  until a graph/identity contract is decided; no serializer or silent nested
  copy is introduced.

These limits prevent claiming the broader all-value-types goal complete. The
current API report records other missing operations individually; no historical
rationale is invented for an unbound operation.

## Post-campaign disposition

The completed inventory leaves 104 distinct methods with a limitation: 98
without bindings and six bound methods with a reproduced semantic gap. The
generalized `meta` declaration and the model in
[Meta-function Lifetime Equivalence](../docs/src/internals/meta-lifetime-equivalence.md)
change how that remainder should be assigned. They do not reopen the methods
whose exact native contracts are unsuitable for compile-time execution.

| Disposition | Methods |
| --- | ---: |
| excluded exact native contract | 29 |
| generated by type and function adoption | 44 |
| generated after lifetime-effect certification | 6 |
| generated after borrow or finalizer certification | 4 |
| explicit signature adapter required | 13 |
| another represented abstraction required | 2 |
| bound behavior defect | 6 |

The 29 excluded methods are not ordinary binding debt:

- Nineteen allocation, destruction and ownership operations:
  `String.free`, `String.intern_free`, `String.is_permanent`, `String.malloc`,
  `String.new_in`, `String.promote`, `String.try_own`, `List.cons_in`,
  `List.promote`, `List.try_own`, `Array.cleanup`, `Array.free`,
  `Array.list_free`, `Map.cleanup`, `Map.export_to`, `Var.move_wide_to`,
  `Var.register_object_tag`, `Var.try_export_context` and `Var.wide_owner`.
- Eight operations that require an actual native address or pointee layout:
  `Var.dispatch_truth`, `Var.numeric_decode`, `Var.numeric_info`,
  `Var.pointer`, `Var.postfix`, `Var.try_dispatch_binary`,
  `Var.try_dispatch_unary` and `Var.update`.
- `String.c_find`, whose result is a borrowed interior C pointer, and
  `Var.pointer_string`, which observes native address identity.

Forty-four methods become declarative candidates rather than individual
adapter work once marked types and functions generate their descriptors,
accessors, function pointers, names and session registrations. They are the
16 Buffer writers and converters, `Array.block`, `Var.block`, the 22 packed
typed Array and Map conversions, `Var.jsonbool`, `Var.regex`,
`Var.regexcapture` and `Var.regexmatch`. Existing `Var` protocols and runtime
owners remain authoritative; generated metadata must replace manual binding
rows rather than create a second inventory.

Six more methods are eligible when their callback and allocation effects have
complete summaries: `String.lines`, `String.splits`, `String.words`,
`Var.as_iter`, `Var.fallback_iter` and `Var.adnode`. Four borrowed or
finalized handles additionally need their owner or exact-once finalizer proved:
`Var.token`, `Var.file`, `List.job` and `Var.job`. Scope ownership is enough
for pure memory. Observable cleanup, such as closing a File or terminating a
Job, must occur at the corresponding evaluator region boundary rather than be
delayed indiscriminately until the compile-time session ends. Effectful File
and Job operations also remain explicit trust choices even when their memory
lifetimes are certified.

The generalized marker does not make an unrepresentable C signature safe.
Thirteen methods still need deliberate adapters: `String.c_compare`,
`String.c_len`, `String.open`, `String.printf`, `List.concat_n`, `List.list_n`,
`List.unpack_n`, `List.unpack_vars_n`, `Array.update_n`, `Map.update_n`,
`Symbol.decode`, `Symbol.new` and `Var.new`. `Var.bytes` still needs a safe
owner-relative view instead of a possibly stale raw pointer, and `Var.matmul`
needs a represented matrix type and protocol. The six bound defects remain
ordinary parity repairs: `String.hash`, `String.lstrip`, `String.rstrip`,
`String.strip`, `Symbol.first` and `Symbol.last`.

The lifetime claim is an ownership-effect simulation, not merely matching
call names. A proof-bearing `meta` surface must derive or record allocation
owner, borrowing, retention, transfer, early release, result provenance and
finalization for each binding. A dual-form function is certifiable only when
its native form is region-clean under complete summaries and its interpreted
bindings have equivalent or safer ownership effects. The current region pass
is advisory, so compilation alone does not yet establish that premise.

### Meta-capable protocol opportunity

Generalized `meta` declarations and protocols should compose rather than own
parallel registries. Their roles are orthogonal:

- `meta` says that a declaration is available during translation;
- a protocol says how a type behaves;
- `protocol Var(T)` supplies representation, boxing, unboxing, identity or
  value-copy behavior and dynamic tags;
- `protocol Cleanup(T)` identifies destruction that must participate in the
  type's ownership contract; and
- other protocols supply methods, forwarding and associated types.

The opportunity is to make a protocol, or selected protocol requirements,
meta-capable. The exact syntax remains a design choice; an illustrative form
is:

```x2c
meta protocol Iter(T) {
  associated Value = Var;
  int T.try_next(T, Value *);
}

meta Split;
protocol Iter(Split);
```

Adopting that protocol could generate both the native witness and its
compile-time witness from the same conformance. The compiler could resolve the
associated types, verify that each crossing is representable, generate any
required output-cell thunk, install the callable entries in the compiler
session and attach the same ownership-effect summaries to both realizations.
An `as` adoption could reuse the represented type's witness instead of
building another adapter. REPL discovery could follow visible meta-capable
conformances rather than a separate API list.

This composition could make protocol witnesses the canonical source of many
generated meta bindings. It would reuse the existing owners of conformance,
associated types, forwarding, placement, visibility and generated thunks.
Binding-specific metadata would remain only for real representation-changing
adapters. Lifetime certification could record allocation, borrowing,
retention, transfer, provenance and finalization on a protocol requirement or
implementation once, then reuse that fact in native region analysis and the
evaluator-equivalence check.

Meta availability must remain explicit. Marking a type `meta` should not
expose every method it happens to have; a method must be individually marked
or reached through a deliberately meta-capable protocol. Associated types must
also have a valid meta representation. File, process, mutation and unsafe
operations remain trust decisions even when their signatures and lifetimes
are representable. Ordinary source order, protocol placement and visibility
continue to govern what a unit can see.

Do not introduce a public `protocol Meta(T)`. That would duplicate the
contextual keyword and conflate phase availability with behavioral
conformance. Field accessors for evaluator or native records are generated
representation machinery, while protocols describe the behavior intentionally
published for the type. The generalized type/function work should preserve a
metadata seam for protocol witnesses before its registries and native-record
descriptors harden, but this opportunity does not add implementation to the
completed represented-value campaign.

This campaign therefore stops at the represented-value boundary it delivered.
The local generalized declaration and record implementation was rejected before
publication; its repair is tracked by the
[meta recovery plan](archive/meta-recovery.md). Meta-capable protocol
witnesses and lifetime certification remain coordinated compiler, runtime and
analysis work; do not maintain temporary manual rows that work is intended to
delete.

## No-value transport

The transport implementation keeps the established truth contract. Lisp
predicates still return Symbol `true` or nil, and Lisp conditions treat nil and
`void` as false. It does not adopt numeric predicate results or change runtime
`Var.truth`.

Raw evaluator slots now preserve `void` through fixed calls, `Var` arguments and
results, globals, locals and captures. Native declared-void functions, block
lambda fallthrough and bare returns, and meta fallthrough and bare returns all
produce the same no-value. Rest calls reject `void` before packing a List;
concrete typed value arguments and ordinary List, Array and Map storage continue
to reject it. Missing List/Array/Map reads and removals now preserve `void`
instead of collapsing it to an empty List. Existing direct `Context.export(void)`
behavior remains unchanged.

The compiler transition is staged through the generated bootstrap rather than
hand-editing it. Focused native, meta, interpreter, instrumented VM, absence and
header-cache probes cover the transport and the first-failure diagnostic path.
The iterator integration adds a session-bound callback bridge and private
Scope-owned iterator destinations while preserving the public caller-storage
APIs. List, Array and Iter folds retain the void no-seed marker; empty Iter
`next`, `find`, `min` and `max` results remain true void. Focused probes cover
null callbacks, empty inputs, callback truth, laziness and session lifetime.

The absence-wrapper audit has three dispositions:

- List `getindex`, `last`, `assoc`, `get`, `caar`, `cadr` and `caddr` preserve
  `void`; `caar` stops when either selection is absent.
- Array `getindex`, `setindex`, `take_last`, `shift`, `remove` and `insert`, and
  Map `get`, `getindex` and `del`, preserve `void`.
- Predicates, indexes, default-taking operations and mutators that return a
  receiver or count retain their native non-absence contracts; they need no
  `void` wrapper.

## Plan review

The parser and typed AST establish grammatical shape and declared types; capture
normalization establishes template argument structure. Consumers reuse these
facts. Normal binding owns scopes, fresh names, placement and typing. Canonical
hand-built Lists remain accepted without origin authentication or another AST
validator.

Reuse the existing evaluator, numeric scanner/type owner, capture rows, deferred
invocation and binder. Delete duplicated scalar conversion and manual fixed AD
output construction as their replacements land. The only intended lasting new
surface is explicit meta execution plus template construction in the defined
context; the inventory tool is optional reporting. No second binder, generic
serialization framework, speculative cache or unrestricted text rewrite.

The source should express calculations as meta functions, fixed generated code
as source templates, and input grammar as Match. This keeps ordinary x2c binding
and ownership rules responsible for meaning.

Reuse current diagnostics. Rejection of an unresolved explicit call protects
its promised execution phase; rejection of an unrepresentable result prevents
wrong values or unsafe embedded addresses. Compatibility cases protect existing
expression macros and collision behavior. Hygiene, conversion and callback
cases detect wrong generated output rather than merely earlier errors. No
additional validator or dedicated diagnostic is proposed without one of these
concrete requirements.
