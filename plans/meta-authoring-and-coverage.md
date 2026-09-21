# Meta authoring, literal results, and API coverage

> Status: active
> Gary approved execution and all five recommended decisions on 2026-09-20.
> The initial implementation shipped in 8ebb323d. Value aliases and further
> AD source templates shipped through 8c2a8054; x2c-first examples followed in
> 95e73d18. Capture-call repairs and remaining API/representation work extend
> that baseline. The exhaustive value-operation continuation now accounts for
> all 483 signatures with 305 bindings and behavioral evidence for every bound
> row. Implemented behavior and open follow-ons are recorded below.


## Outcome and priorities

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

Treat general Iter support as a bounded representation task: account for state,
next callbacks, auxiliary Func values and caller-owned lifetimes. Choose a
representation using existing runtime/evaluator facilities before promising all
iterator operations. The goal is principled functional coverage, not adding
individual names until examples happen to pass.

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
APIs into the implicit prelude. The resulting inventory has 305 binding matches
and 178 unmatched signatures. Its fixed native/meta comparisons leave no bound
row unverified: 295 rows have a verified example and 15 retain a reproduced
limitation. The other 173 unbound rows have an explicit owner, contract group,
disposition and next action. The optional inventory records every signature and
distinguishes observed behavior from binding presence and absence.

Three representation follow-ons remain explicit rather than being presented as
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
- General Iter, including Map.keys, contains caller-owned state and a native next
  callback. It needs an evaluator representation and adapter whose state/lifetime
  contract matches native iteration. Map.keys is not a missing List-return alias.
- List.foldl distinguishes a void seed from an empty List and permits a null
  callback. The current Lisp value channel cannot preserve true void. Full parity
  requires that value representation decision before adding an alias; ordinary
  seeded folds can already be written as meta functions.

These limits prevent claiming the broader all-value-types goal complete. The
current API report records other missing operations individually; no historical
rationale is invented for an unbound operation.

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
