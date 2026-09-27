# Macros as construction templates and structural Match patterns

> Status: reference - research spike, 2026-09-27, baseline
> `1b23aaa7e103461c3b219b9e10546aeb35384b60`.
> Investigation and isolated prototypes only. No production feature,
> bootstrap refresh for publication, commit, push, or merge is authorized.
> The recommendation is supported for fixed structure, scoped identity
> mapping, transparent helper data and contextual Match retry prototypes.
> Phase-2 surface and completeness evidence is recorded in
> [dual-macro-values-validation.md](dual-macro-values-validation.md).

## Architectural recommendation

A macro value contains its canonical AST body, parameter definitions,
introduced declarations and captured bindings, all inspectable as ordinary
data. Construction and recognition interpret that same body. Construction
supplies hole values and allocates introduced declarations; recognition finds
hole values and aligns introduced declarations with existing ones. Use the
existing Match engine for structure and the existing macro expansion machinery
for freshening, substitution, and ordinary binding. Do not introduce another
program AST grammar, another name resolver, or an inverse evaluator.

Keep compiler-issued binding identities authoritative. Introduced declarations
have template-local slots, assigned by lexical declaration position and
namespace. Matching establishes a bijection from these slots to the subject's
bindings. Free references stay rigid in their compiler domain. Captures retain
original code plus the interface connecting references to surrounding
matched declarations. Names neither establish nor destroy binding identity.

Named and anonymous macros produce the same value representation. Named
references are sufficient to prove the core; anonymous macro literals are
included in this specification and implementation plan.

Contextual equality and scope correspondence must join Match's retry machinery. A post-check of its first
successful structural result is incomplete for interior sequence holes. A
bounded internal comparison/acceptance interface using the existing choice
journal is recommended; resumable structural candidate enumeration is viable.
The bounded relation interface has now passed isolated runtime tests, including
deferred checks after a later declaration capture. Automatically deriving those
checks from macro bodies is still unproved. A second concrete
integration question is the binding-domain bridge for templates compiled into
the native helper: helper-build IDs must never masquerade as program IDs.
Transparent skeletons plus a supplied current-domain environment are viable.
Explicit captured-reference hydration now passes actual native helper tests;
automatic definition-site capture registration remains unproved.

## Evidence and what it establishes

Primary source owners, checked against this baseline:

| Current owner | Existing behavior | Consequence |
| --- | --- | --- |
| `src/macros.x:3370-3390`, `3097-3199` | `macrodef` and `macro-param` are ordinary Lists; kinds are grammar categories inferred from body positions | Extend the existing definition/interface; `Expr` does not mean a C type predicate |
| `src/macros.x:2832-3011` | capture rows have source/value/expression/splice projections | One logical hole needs role-specific projections, not a textual `$` to `?` rewrite |
| `src/macros.x:2741-2812`, `3634-3693` | introduced locals/tags get ordinal replacement binders; all uses are rewritten through an identity map | Reuse declaration identity and existing fresh rows |
| `src/macros.x:3995-4114` | invocation rows match once, template replaces once, fresh declarations allocate once, output calls `bind_syntax` | Existing `pattern` matches arguments, not the body being recognized |
| `src/ast.x:32-64`, `src/compiler.x:2852-3026` | binding Lists have positive identity and name; scopes own identity lookup | Alpha comparison must preserve declaration/reference incidence |
| `src/expressions.x:1330-1403` | definition-site capture protection differs from ordinary stale-local handling | Carry capture roles explicitly; IDs alone do not guarantee preservation on rebinding |
| `src/parse.x:2422-2473` | ordinary binder mutates semantic state and expands deferred invocations | Matching must not speculatively bind or execute expansions |
| `lib/match.x:730-762`, `1158-1171`, `1417-1478` | replacement splices sequences; repeated captures use equality; interior stars retry shortest first | Reuse structural matching; extend contextual equality inside retry |
| `lib/match-machine.x:108-111` | repeated value slot comparison uses `Var ==` | Existing equality is not alpha-equivalence |
| `lib/list.x:825-850` | `List.equal` uses canonical chain identity; `List.compare` compares content | Specify equality independently of allocation/boxing |
| `src/stage.x:681-700`, `src/macros.x:4151-4167` | staged Unit/block calls become `tpl-call`; Expression macros do not use this constructor route | Unapplied and anonymous values are new functionality |
| `etc/meta-helper.x:129-176`, `src/macros.x:2329-2338` | helper returns `("x2c.template" stored values)`; compiler recursively resolves these markers; compiler queries unavailable in helper | Transparent invocation data exists; descriptor payloads need stage-aware traversal |
| `lib/datum.x`, `src/meta-project.x:366-444` | copyable datum transport and project helper ownership | No opaque-template requirement follows from process separation |
| `src/macros.x:1391-1415` | cached imported globals rebind across symbol resets | Numeric identities are unit/session-relative, not durable global names |

The architecture and public contract are in
`docs/src/internals/architecture.md:260-281` and
`docs/src/reference/language.md:1872-1894`. AST producer origin is deliberately
not authenticated. Existing fixtures supply compatibility examples, especially
`macro-template-lexical-shadow`, `macro-local-lambda-capture`,
`macro-match-binder-literals`, and `meta-template-calls`.

Working isolated evidence is in `.context/dual-macro/`; logs are in `debug/`.
The root session reran the workers' model and transport probes independently.

| Probe | Observed result | Limit |
| --- | --- | --- |
| `baseline.x` | named sum/twice/call construction, meta echo, repeated-hole mismatch, empty/nonempty sequence reconstruction pass | Existing macros plus independently written AST patterns; no unapplied macro reference |
| `shared-list.x` | one canonical `expr/op +` List passes between two meta functions, matches captured program code, and reconstructs it; subtraction falls through | Shared body is handwritten canonical AST; source-template compilation is not implemented |
| `macro-template-lexical-shadow.x` | existing fixture runs, prints `28 28` | Existing construction hygiene, not alpha recognition |
| `negative-braces.x` | current compiler rejects braced Expression body with its documented parse diagnostic | Rejects that current name only, not dual-use semantics |
| `alpha-model.py` | alpha rename, shadow mismatch, free mismatch, boundary extraction/rebase, escaping failure, hole-local preservation, injectivity and sequence post-check counterexample pass | Python model with supplied ownership metadata; no full binder discovery or Match integration |
| `cross-capture-model.py` | joint map preserves references between captured regions; two output copies stay distinct | supplied relocation maps, not compiler discovery |
| `transport-datum-probe.x` | transparent descriptor data roundtrips, including repeated reference records and marker-shaped ordinary Lists | Dummy identity 912 and illustrative local-slot data are not valid executable compiler bindings |
| `transport-helper-probe.x` | actual project helper runs descriptor -> relay -> inspect, prints `helper descriptor inspection: 1` | Tests data inspection, not source anonymous templates, executable reconstruction, or resolved free identities |

`make build-safe` succeeded before compiler probes. No publication gates were
run: production code was not changed. These are feasibility probes, not a
claim that the complete feature exists or that the full corpus was tested.

A failed nested `$inspect($relay($descriptor()))` experiment attempted to
insert returned Lists as code. Ordinary calls inside a meta pipeline work.
This establishes a staging boundary that explicit macro-value syntax must
address; it does not establish that transparent values are impossible.

## Specification: values before surface syntax

There are five distinct things:

1. **Definition:** a registered named macro, with existing visibility and
   argument/result categories.
2. **Unapplied template:** a snapshot of that structural body/interface and
   lexical environment, independent of later same-named redefinitions.
3. **Invocation:** a template plus supplied capture rows, without expansion.
4. **Constructed code:** substituted canonical macro/parser code, possibly
   still containing nested invocations or computation slots.
5. **Bound code:** ordinary compiler binding/typing has run in a particular
   `AstPos`, lexical environment, and return context. Lowered backend code is
   a further stage and is not automatically reversible into source code.

A transparent descriptor can reuse `macrodef` fields. The following shows
logical fields, not a second grammar for ordinary code:

```text
macro-value
  result-kind, parameters, template, fresh, captures
  slot-roles, stage, compiler-domain, origin
```

`parameters` retains canonical `macro-param` rows. `template` is the same
canonical AST List used for construction; it retains existing replacement
binders and quoted literal contexts. `fresh` retains local ordinal, namespace,
label and scope/declaration correspondence. `captures` holds rigid lexical
references and any explicitly supplied transportable meta values.
`slot-roles` associates actual hole occurrences with their grammar slot and
projection. Retain this association while parsing/finalizing holes instead of
recovering it by an unrestricted scan of binder-looking atoms.

`stage` distinguishes a body, invocation and code bundle; it is operational
metadata, not producer authentication. `compiler-domain` bounds interpretation
of free semantic IDs. Ordinary raw canonical Lists remain accepted at existing
code insertion points; a legal shape does not need template provenance.

A recognition capture row contains its logical hole identity, grammar kind,
original code, owned declarations, references to enclosing template slots
and to declarations owned by other captures, rigid external references, and
available source association. Capture rows share an ownership/reference graph;
a declaration in one sequence element can bind a reference in a later element
or another hole. A sequence is one region for alpha comparison, not a List of
independently closed elements. A construction bundle contains canonical code plus its fresh-local/boundary interface.
These are ordinary inspectable Lists. The original AST is authoritative; a
comparison projection is transient, not a second tree shipped to the binder.
Concrete proposed data shapes (field names are a proposed contract):

```text
(macrodef
  (name sum) (kind expression) (target ()) (targetp ())
  (parameters
    (macro-param (binder ?left) (kind expr) (sequence 0))
    (macro-param (binder ?right) (kind expr) (sequence 0)))
  (template (expr (<macro-expr>)
    (op + ?__macro_expression_left ?__macro_expression_right)))
  (fresh ()) (captures ()) (pattern INVOCATION-ROW-PATTERN)
  (stage template) (domain "unit/session")
  (roles (left expression PATH-LEFT) (right expression PATH-RIGHT))
  (origin ()) (file "source.x"))

(macro-capture (hole left) (kind expr)
  (value (expr (int) (ident (binding 41 "price"))))
  (owned ()) (boundary ()) (cross-capture ())
  (free (binding 41 "price")) (source ()))

(code (stage constructed) (domain "unit/session")
  (ast (expr (<macro-expr>) (op +
    (expr (int) (ident (binding 41 "price")))
    (expr (int) (ident (binding 42 "tax"))))))
  (fresh ()) (captures ()) (boundary ()) (relocations ()))
```

The macrodef retains its existing invocation-row pattern, rather than storing a
second authored body pattern. Paths locate registered substitution positions;
they do not resolve names. Existing parser output owns precise body wrappers
and internal binder names; this example illustrates that canonical shape,
not an assertion of a new exported ABI already present today. The code bundle
is an insertion envelope, not a program AST node: the compiler adapter prepares
fresh/relocated bindings through existing expansion, unwraps `ast`, and calls
ordinary binding at the caller-owned transaction boundary. Returning a bundle
from a List-returning meta function is therefore explicit new insertion support.
Raw canonical code Lists continue through their existing path.

Use immutable Lists for the descriptor/interface. Prepared Match plans and
caches are process-local derived state and do not cross the helper wire.
Copyable scalars/Strings/Symbols/Atoms/Lists cross through existing datum
transport. Native pointers/Func environments do not: the helper is another
process. Mutable collection alias/cycle limitations remain those of datum
transport; they do not justify making a template opaque.

## Holes, projections and substitution

A hole is a template metavariable, not a program declaration. Its stable
identity is the parameter slot in its template; its name is a user label.
Nested template composition renames slot identities to prevent accidental
capture even when both templates call a parameter `$value`.

- `Expr`, `Type`, `Name`, `Decl`, `Function`, `Statement`, etc. retain current
  grammar-category meanings and inference rules. Recognition captures code
  of the corresponding slot category. Semantic C type constraints are ordinary
  explicit meta predicates on carried Type data, not a second type checker.
- Repeated occurrences of one hole require the same category and equivalent
  code under the declared recognition relation. For a bound identifier this
  requires the same external binding; for a closed block it allows alpha
  renaming of that block's own declarations. Names alone never suffice.
- Distinct holes may capture equal values. Conversely distinct introduced
  declarations must not map to the same subject declaration.
- Sequence holes capture an ordered List of elements of one category, including
  empty sequences. Retain current final invocation-parameter restriction.
  Body splice positions may be interior. Matching enumerates valid partitions
  shortest first, and all contextual constraints participate in retries.
  Repeated sequences compare as ordered regions with one shared local map and
  boundary interface, preserving declaration/reference relationships across
  elements.
- Capture projections derive from one captured grammar value. `Name` in an
  expression supplies an `ident` shell; in a member slot it supplies name;
  in a declarator it participates in declaration identity. These projections
  cannot be captured independently with inconsistent values.
- `Type` is a structural List splice at its existing type position. Function
  return/declarator projections and source/value/expression/splice projections
  reuse the existing machinery. Recognition cannot fabricate missing source
  text or compiler-computed Type descriptions.
- Total application requires every parameter, including those unused by the
  body. Missing substitutions are errors at the application interface; explicit
  partial application can later produce a new template, but is not silently
  inferred from `List.replace` retaining missing binders.
- An unused hole cannot be discovered by body recognition. Recognition returns
  it as absent; construction of a roundtrip must supply it or the template must
  explicitly project it away. A hole seen only through an arbitrary computation
  is likewise not recoverable. This is information loss, not implementation
  inconvenience.

Literal pattern-looking atoms, including `?__macro_expression_value` and
`*__macro_splice_items`, remain literal when the AST contains them as data.
Operators such as `*`, fields, labels and grammar tags likewise keep their
roles. Pattern preparation uses `!quote` or an equivalent existing literal
lowering path for payload values; it does not reinterpret every Atom.

## Normalization, binding and hygiene

Define alpha-equivalence relative to a region and a compiler domain. Every
owned declaration has one slot, with its namespace, declaration position,
scope and visibility region. Every reference points to that declaration's slot
or to a rigid external binding identity. Template-local numbering is a label
for the relationship, not an absolute path baked into emitted code.

During recognition align **fixed template declarations** by their structural
positions, excluding subtrees swallowed by holes. Match the candidate identity
field into a local slot, ignore its name label, and require every fixed
reference to that slot to reach the same candidate identity. Enforce
injectivity across distinct local slots and corresponding lexical ownership.
A whole-subject preorder numbering is wrong: declarations inside a captured
prefix must not shift the ordinal of a later fixed declaration.

For example, template `{ $prefix... int fixed; use(fixed); }` has fixed local
L0 even if the captured prefix declares two locals. The subject's `fixed`
declaration is matched by its structural position, not its global ordinal 2.
Existing ordinary binding supplies scope/namespace/reference facts. Extend its
output metadata where needed; do not write another name-resolution pass over
arbitrary Lists.

Within a captured subtree, declarations it owns get a capture-private alpha
map. References to surrounding fixed locals become boundary references to the
established template slots. References to declarations owned by another captured region retain a
cross-capture edge, rather than being misclassified as rigid free references.
Other free references keep their exact identities.
On construction, build one joint relocation map for the output region,
freshen each relocated declaration once, and remap only
references to that declaration. A capture referencing surrounding L0 may be
inserted under a reconstructed L0 through an explicit map. It may not escape
into a scope without that declaration. A rigid free reference is never rebased
merely because a destination local has the same name.

Freshening must cover declarations inside inserted hole code as well as
fixed introduced declarations when copying creates a new executable region.
Recognition returns original code without eagerly cloning it. Reusing a
capture twice in value positions preserves references to its external bindings;
copying declaration-bearing regions twice creates distinct declarations and
consistent internal references per insertion. If another capture refers to
that declaration and it is copied twice, its destination occurrence must be
explicitly mapped; reject ambiguous relocation instead of selecting by name.
For example, Hprefix = `int x;` and Hvalue = `x` share one edge. Rebuilding both
once maps both to fresh-x. Copying Hprefix twice and Hvalue once requires an
explicit target occurrence. The cross-capture model exercises a supplied joint
map, but automatic metadata discovery and ambiguity handling in the compiler
remain implementation work.

Identifier roles:

| Role | Construction | Recognition |
| --- | --- | --- |
| Template-introduced declaration/reference | existing fresh row allocates one identity; every use follows it | alpha correspondence by declaration/scope/namespace |
| Literal definition-site free reference | retain captured identity and existing capture protection | rigid identity in originating domain |
| Hole-supplied reference | retain call-site identity, except explicit relocation map | capture with boundary/free interface |
| Hole-supplied declaration | ordinary declaration publication/freshening policy for its slot | capture declaration region and its references |
| Public tag/member/field/label | existing namespace and member-name rules | compare according to that grammar role; no local-variable alpha rename |
| Unqualified unresolved textual name | ordinary binder resolves in specified context | structural name only until resolved; cannot claim alpha identity |
| Explicit `x2c.ident` public-name request | ordinary exact-name publication/resolution | match marker at open stage or resolved identity at bound stage, never conflate them |

Current `_resolve_identifier` may retarget stale ordinary local identities to
visible same-named locals. The new capture interface must reuse/extend
existing lexical capture protection for preserved code references. It cannot
assume any positive ID survives all rebindings unchanged. Unknown identities
still fail in the ordinary binder; no opaque capability or origin seal is added.

Numeric identities remain unit/session-local. Helper calls for a unit can
carry program code IDs unchanged. **Compiling the helper itself is a different
binding domain**: `src/meta-project.x:120-132` parses its units separately, and
`src/stage.x:758-772` borrows those build-compiler bindings. A cached native
helper therefore cannot embed its build-time IDs and use them to recognize
program references. Existing global `tpl-call` sidesteps that problem by
transporting a name for the active compiler to resolve.

Recommended transparent domain bridge:

- Compile a named reference or anonymous literal in a helper to a descriptor
  skeleton, indexed by owning source/declaration path and explicit external
  reference slots. Its body remains canonical code with the existing binding
  records; the descriptor's environment marks which records await rebinding.
  A lexical key selects an environment entry, not permission to construct ASTs.
- Ordinary program parsing registers the same literal/definition and resolves
  its definition-site references through existing binding operations. Send an
  inspectable map from skeleton keys/reference slots to current-domain binding
  records or complete descriptors with each applicable existing helper request.
  No nested callback is required. Local references need lexical registration;
  a global name fallback cannot resolve a local closure correctly.
- The helper hydrates a skeleton from that request environment before semantic
  recognition. A missing environment leaves an open descriptor inspectable,
  but cannot claim bound alpha matching or insert helper-build IDs as program
  references. Captured program code arguments already carry the correct
  program IDs. Name/member/type roles continue to use their own projections.
- Native helper locals are meta values, not program declarations. Capture such
  values by explicitly binding them into typed template holes; a List may carry
  program code and an integer may become a literal. Do not transport a C local
  variable's binding ID as a captured program reference. Anonymous literals
  formed directly in ordinary program lexical code capture that context's
  program references through its compiler-owned interface instead.

This bridge is proposed, not executed. An even smaller first experiment passes
an already hydrated template explicitly as a meta argument from the active
compiler, using the same data API. That proves dynamic construction/recognition
without proving macro-reference/literal availability inside precompiled helper bodies.
The full implementation still includes those forms and their environment.
A descriptor cannot be reused after that binding domain has been destroyed. Imported global references use the existing import-rebind
boundary; portable persistence of captured local IDs is not promised. Names
used by that global rebinding boundary are not a reason to compare local frees
by name.

## Match integration and equality

A macro value is called to build code and used as the callee in a Match case
to recognize code. The public forms are `sum(left, right)` and
`case sum(?left, ?right)`. The existing Match engine publishes captures only
on success. Its internal out-parameter API still distinguishes empty success
from a miss; users need no separate template matching method.

A call in meta code returns an inspectable code value. Inserting that value
into a program uses existing macro expansion and `Compiler.bind_syntax`.
Matching never inserts, expands or evaluates the candidate code. The different
stages remain part of the value contract, not separate public verbs.

Compile recognition from the same body and parameter metadata into existing Match
structural forms. Fixed local identities use internal capture slots. Hole
occurrences have separate internal slots if needed to compare alpha-equivalent
values. User capture publication maps these back to logical parameter slots.
Reuse `MatchCaptureLayout`, plans, sequence matching, atomic capture publication
and replacement. A derived plan is a cache, not another authored pattern body.

Contextual comparison must be part of a Match attempt: declaration bijection,
repeated-hole alpha comparison and sequence boundary consistency can cause the
current attempt to fail and retry. The existing machine journal/marks are the
starting point for reversible writes. Preserve existing `List.match` equality
and static-pattern behavior when no contextual policy is supplied.

Counterexample to post-checking only the first result:

```text
pattern: occurrence1, *between, occurrence2, *tail
subject: alpha-A, different-B, renamed-alpha-A
```

The shortest structural split chooses B as occurrence2. Its contextual check
fails; a later split chooses renamed-alpha-A and succeeds. The isolated model
reproduces this. Plain existing guards cannot express arbitrary contextual
comparison. A public wrapper around committed `try_match` is therefore not a
complete implementation.

Three equality relations must stay distinct:

- **Datum/structural equality:** canonical node roles and content equal,
  including binding identities where present. Do not use allocation addresses
  as a portable wire equality. Source locations/provenance are separate.
- **Alpha-equivalence:** same grammar structure and explicit code,
  bijection on owned declarations, rigid frees equal, compatible boundary
  interface. Inferred `expr TYPE`, inferred `return RETURN-TYPE`, `(at ...)` positions
  and definition-parser placeholder wrappers can be projected away where the
  stage contract permits. Explicit source types are retained. The producer-owned
  inventory of other derived fields is still required; blanket type erasure is
  not specified.
- **Equality after ordinary binding:** in the same admissible insertion context,
  reconstructed code resolves to corresponding declarations and external
  identities and receives corresponding ordinary types. This is not algebraic
  or runtime observational equivalence of arbitrary programs.

Keep explicit casts, declaration/parameter types, modifiers, operators and
member names in the comparison. Abstract only known derived metadata. Do not
erase protocol dispatch targets or lowered conversion calls to invent source
code that the captured stage no longer contains.

## Code stages and expansion policy

| Subject stage | What can be matched | Compiler context |
| --- | --- | --- |
| Unapplied descriptor | body/interface data or template identity | none for inspection; free-ID meaning needs domain |
| Open/deferred code | invocation structure and exact grammar shape | none for structure; no alpha claim for unresolved names |
| Identity-bearing parser/macro code | source-like body pattern, if declaration/reference metadata is present | metadata supplied by ordinary parse/bind owners |
| Bound/typed capture | the structure actually present, with defined metadata projection | no new lookup in helper; types/facts travel as values |
| Lowered AST | literal canonical lowered patterns | cannot promise inverse lowering |

For Statement/Unit and other sequence result categories, the template root is
`seq`, not a scope. Recognition at a single-item position adapts one subject
item to `(seq ITEM)`; at a sequence position it uses the supplied item sequence.
It never flattens a `block` into its contents or adds braces. Thus a macro body
containing a literal block requires that block shell in the subject. Expression
patterns use the expression root with no sequence adaptation.

A body pattern never silently expands a deferred invocation. Invocation
recognition compares the snapshotted definition/interface and its argument
rows. Body recognition compares constructed code. Explicit expansion runs
once in compiler context with existing recursion limits, transactions,
`AstPos`, return type and publication rules. No helper callback channel is
required to inspect or structurally construct an unapplied body.

Snapshotting captures the outer definition and its resolved lexical references.
It does not silently freeze the entire evaluator session. Already stored nested
definitions remain captured; nested name/local-macro markers retain their
existing expansion-time resolution unless explicit structural composition
resolves and captures that child. Computation slots retain their existing
session/effect behavior. Transitive freezing could be a later explicit API;
it is not the default and need not create cyclic descriptor data for recursion.

Nested structural templates can be inlined for recognition after parameter
substitution and hygienic slot renaming. A nested deferred invocation can
instead be retained and matched as an invocation; the caller selects the stage.
Composition must not overwrite child rigid free identities.

Arbitrary `$helper(...)`/Lisp slots are computation, not reversible code.
Recognition of their invocation is structural. Recognition of their expanded
output needs an independently available structural body or a frozen evaluated
fragment. Evaluation to freeze a slot is explicit, with its existing effects
and context; matching never runs it backward or speculatively. A macro may
therefore remain usable for construction while body recognition reports an
unsupported computation slot, or the caller may provide its structural view.
This restriction has a concrete information-loss/effect justification.

## Proposed syntax

The previous surface mixed a special getter, a contextual case introducer,
dotted methods and prefixed APIs. That proposal is withdrawn. The revised
surface has one idea: a macro can be a value, called to build code or used in a
Match case to recognize code. These forms are proposals, not current features.

```x2c
macro Expression $sum(Expr $left, Expr $right) => $left + $right;

// Proposed: referring to a macro without calling it produces a value.
Macro sum = $sum;

// Call it to build an addition from two pieces of code.
List result = sum(left, right);

// Use the same value to recognize an addition and capture its operands.
match (expression) {
  case sum(?left, ?right): consume(left, right);
}
```

In this example, `left` and `right` are code values supplied by the surrounding
meta function. `expression` holds the code being examined. If it holds
`price + tax`, the case captures price code as left and tax code as right.
It does not evaluate price or tax. If it holds `price - tax`, the case fails.
`Macro` is a proposed value type, represented by ordinary canonical Lists,
not an opaque native handle. It identifies callable macro values without
making every List callable or changing ordinary List matching.

The dollar sign and parentheses have separate jobs:

| Reference | Without parentheses | With parentheses |
| --- | --- | --- |
| Named macro | `$sum` obtains the macro value | `$sum(left, right)` applies the named macro |
| Variable declared `Macro sum` | `sum` reads the variable | `sum(left, right)` applies its current value |

`$sum` and `sum` can therefore refer to different macros. `Macro` is the
variable's type; capitalization does not itself select a macro. In a Match
case, either call form recognizes code instead of constructing it. Inside a
macro body, `$left` still refers to a macro parameter, as it does today; the
declaration and lexical context distinguish a parameter from a named macro.

Existing local macro definitions already permit calls without a dollar sign.
This proposal preserves that behavior and the existing `(name)(arguments)`
escape to an ordinary function call. Bare `name` currently remains an ordinary
value even when a local macro has that name. A new first-class reference rule
must preserve those existing function references; it must not claim every
unprefixed name as a macro value.

`$sum` as a value is new behavior. The current compiler only supports the
existing named definition and invocation forms; this plan does not assume
that an unapplied reference works already. The value captures the visible
outer definition and its binding relationships. Existing named calls keep
their meaning. Within `case`, the surrounding Match context makes the call
shape a pattern instead of a construction; no extra introducer is needed.

Phase 2 exposed a staging compatibility question: routing all named
Expression calls inside meta bodies to deferred construction would change
existing helper computations that expand macros while compiling the helper.
The conservative rule preserves that expansion behavior and uses a Macro
value call to construct code data. Context-directed named construction is an
alternative requiring focused evidence; `meta_body` alone is insufficient.

A macro value passed to a meta function works in the same way:

```x2c
meta static List left_operand(List expression, Macro addition) {
  match (expression) {
    case addition(?left, ?right): return left;
  }
  return NULL;
}
```

`addition` is an ordinary parameter holding a macro value. The two captures
refer to that macro's two parameter slots. The compiler must check that the
case and macro interface agree. How much of a dynamically selected macro's
interface is known statically is still an implementation question; simplifying
the notation does not answer it.

Anonymous macros use the same value type and call form:

```x2c
meta static Macro make_addition(void) {
  return macro Expression(Expr $left, Expr $right) => $left + $right;
}
```

For an anonymous Expression macro, the surrounding expression delimiter ends
the body; the return above has one semicolon, not two. Named definitions keep
their existing terminator. An anonymous Statement macro keeps a braced body.
Parser probes must establish these forms without changing precedence or taking
valid existing calls. No braced Expression alternative is required by this
proposal; that independent grammar choice remains open.

Composition is written using nested macro calls in an anonymous body, rather
than a compose method:

```x2c
meta static Macro parenthesized(Macro addition) {
  return macro Expression(Expr $left, Expr $right) =>
    (addition($left, $right));
}
```

The anonymous macro captures addition as a macro value. Recognition follows
its structural body, aligns the child parameters, and preserves binding
relationships across that boundary. Arbitrary meta function calls do not
become reversible merely because they can be written inside a body.
Native helper values are captured as values; program references carried in
code retain the program's binding identities. Phase-2 data prototypes now
demonstrate explicit hydration with actual compiler-issued program references
and an unchanged cached helper after program binding IDs change. Automatic
hydration for arbitrary anonymous program references remains unproved.
The anonymous Macro-callee capture shown here now passes phase-2 factory,
relay, recognition and executable reconstruction tests. A captured
macro call in this example is an
explicit structural composition, rather than an unresolved name looked up
again during expansion.

Call notation determines the operation; the surrounding stage determines
when ordinary compiler binding happens. In a meta body, calling a macro value
constructs inspectable code. Returning/inserting it into a program invokes
ordinary binding and evaluates any deferred child calls when required.
Existing pending call records can be inspected as data. Users do not need
separate construct, invoke or expand methods for these stages.

The ability to call arbitrary Macro values directly in ordinary program source
with Type/Decl/Statement arguments needs more than notation: the parser must
know their grammar categories before parsing those arguments. The initial
value call prototype can accept already captured code values inside meta
functions. It must not be presented as proving fully dynamic source argument
parsing. The final interface policy remains an explicit design question.

## Surface inventory

| Form | Meaning | Status |
| --- | --- | --- |
| `macro Expression $sum(...) => ...;` | Define a named macro | Existing |
| `$sum(a, b)` | Apply the named macro | Existing |
| `$sum` | Obtain that macro as a value without applying it | Proposed |
| `Macro sum = $sum;` | Store a macro value | Proposed type name and value behavior |
| `sum(a, b)` | Call the stored macro to build code | Proposed |
| `case sum(?left, ?right):` | Use that macro to recognize code and capture its parameters | Proposed |
| `case $sum(?left, ?right):` | The same pattern using the named macro directly | Proposed |
| `macro Expression(...) => expression` | An anonymous macro value | Proposed |
| `macro Statement(...) { ... }` | An anonymous macro with a statement body | Proposed |
| `?left`, `*items` | Match captures | Existing notation reused |
| `$left`, `$items...` | Macro parameters and sequence insertion inside a body | Existing notation reused |

There is no new template keyword, getter function, method family or prefixed
public API in this revised proposal. Macro is a type name, not a tokenizer
keyword. Expression/Statement and Expr/Name/Type reuse existing categories.
Composition and passing values use calls, parameters and anonymous bodies.
No general partial application or inverse computation API is specified.

Canonical descriptor fields, capture rows, scope maps and helper environments
remain implementation details that are inspectable as ordinary data. They do
not each require another user-facing operation. Existing names such as
`Compiler.bind_syntax` are quoted exactly to locate their current owners;
this plan does not adopt their terminology for new public names.

## Worked examples and counterexamples

All source below is proposed unless identified as a current fixture. Compact
notation `E`, `D(Ln)`, `R(Ln)`, `F(domain,id)`, `Hn` is explanatory notation for
canonical AST plus side metadata, not an alternative AST code to implement.
`E(op + A B)` corresponds to `(expr TYPE (op + A B))`; D and R annotate existing
`bind`/`ident` binding nodes. Labels are shown only when helpful. Capture rows
abbreviate source/interface fields; reconstruction means ordinary insertion and
binding after pure substitution.

### 1. Arithmetic construction and recognition

```x2c
macro Expression $sum(Expr $left, Expr $right) => $left + $right;
// construct: $sum(a, b)
// recognize: case $sum(?left, ?right)
```

Normalized body: `E(op + H0 H1)`; supplied rows `{H0=R(a), H1=R(b)}` construct
`a + b`. Recognizing `price + tax` returns `{left=R(price), right=R(tax)}` and
reconstructs `price + tax`. `price - tax` fails on the operator; an invocation
of `$sum(price,tax)` at the deferred stage does not yet match this body.
The real `shared-list.x` probe demonstrates the structural roundtrip on a
captured bound expression using one body List, but not the new macro-value reference.

### 2. Repeated holes

```x2c
macro Expression $twice(Expr $value) => $value + $value;
```

Body `E(op + H0 H0)`. `price + price` produces `{value=F(unit,price-id)}` and
reconstructs it. `price + tax` fails. Two references named `x` to different
shadowed bindings fail. Two captured closed blocks with renamed private locals
can satisfy a repeated Statement hole by alpha-equivalence, while differing
free reference identities fail. Existing raw Match repeat probes establish
same-capture equality only; the model establishes the local/free distinction.

### 3. Sequence capture and reconstruction

```x2c
macro Expression $call(Expr $callee, Expr $arguments...) =>
  $callee($arguments...);
```

Body `E(call H0 (args *H1))`. `sum(a,b,c)` returns `{callee=F(sum), arguments=
[R(a),R(b),R(c)]}` and reconstructs it; `sum()` returns an empty ordered List
and reconstructs it. `sum(a)[b]` fails as a whole expression because of the
index shell. Literal `*` is an operator, not this registered sequence hole.
Repeated sequence occurrences require the same order and identities; `[a,b]`
and `[b,a]` fail unless the element values themselves compare equal.
An interior Statement sequence followed by fixed `return 0;` requires retries
that include contextual comparison, as described above. Empty/nonempty final
sequence roundtrips run in `baseline.x`; interior contextual retries do not.

### 4. Declaration alpha-equivalence

```x2c
macro Statement $save(Expr $value) {
  { int temporary = $value; consume(temporary); }
}
```

Body `seq(block(D(L0:int,H0), call F(consume)(R(L0))))`. Subject
`{ int subtotal = price; consume(subtotal); }` aligns `L0 -> subtotal-id`,
returns `{value=R(price)}`, and reconstructs `{ int fresh = price;
consume(fresh); }` with one fresh identity. `consume(other)` fails despite any
similar name. `long subtotal` fails on explicit declaration type.
This distinguishes the hole `value` from the introduced program binder L0.

### 5. Nested scopes, shadowing and free references

```x2c
macro Statement $nested(Expr $value) {
  {
    int x = $value;
    { int x = 1; consume(x); }
    consume(x + external);
  }
}
```

Body `seq(block(D(L0,H0), block(D(L1,1),call F(consume)(R(L1))),
call F(consume)(E(+ R(L0) F(external)))))`. Subject using `outer`/`inner`
returns the initializer for H0 and map `{L0=outer-id,L1=inner-id}`.
Reconstruction freshens both and preserves external-id. Calling `consume(outer)`
inside the inner block fails. Replacing external with a same-named local
fails. Collapsing L0/L1 to one declaration fails. Extracting `R(L0)` into a
capture yields boundary `{outer-id -> L0}`, not a newly invented local 0;
reconstruction outside L0's scope fails. The model exercises these relations.

### 6. Definition-site references and call-site captures

```x2c
int helper(int value);
macro Expression $using_helper(Expr $value) => helper($value);
```

Body `E(call F(helper-definition) (args H0))`. At a caller with a shadowed
`helper`, the hole may contain that caller's reference, but the literal callee
remains the definition-site helper. Recognition of the global helper call
returns `{value=call-site code}`; recognition of the shadowed local call
fails. Reconstruction retains both roles. Generalize recognition with an
explicit `Expr $callee` hole when any callee is intended; making a literal
unqualified identifier implicitly wildcard would destroy hygiene.

A `Name $member` in `$object.$member` instead captures member label `total`;
its normalized representation is `field(Hobject,label Hmember)`, rows are
`{object=R(record), member="total"}`, and reconstruction is `record.total`.
`record.other` with a fixed literal `.total` fails. A Name in `int $name`
creates/captures a declaration, not a member label or a generic Expr subtree.

### 7. Anonymous composition and meta transport

```x2c
// Proposed macro values and structural composition:
meta static Macro wrapped(Macro addition) {
  return macro Expression(Expr $left, Expr $right) =>
    (addition($left, $right));
}
// wrapped($sum) returns the composed macro value.
```

Body `E(parens E(+ Hleft Hright))`, child slot identities renamed into the
composed interface; rows from `(price + tax)` are `{left=R(price),right=R(tax)}`.
Reconstruction gives `(price + tax)`. `(price - tax)` fails. Two child templates
with introduced local named `saved` obtain different child slots per insertion;
identical labels do not merge them. An anonymous literal referring to a local
`bias` captures its rigid code binding and fails against a different bias-id.
Native runtime closure pointers do not cross the helper. Actual data-only
relay/inspection and datum probes pass; the macro literal and captured-call parser and
freshening of multiple declaration-bearing insertions remain unimplemented.

### 8. Deferred versus expanded code

```x2c
// pending holds captured code with an unexpanded $sum(A, B).
meta static List copy_pending(List pending) {
  match (pending) {
    case %(macro-invoke ?definition ?arguments ?site):
      return %(macro-invoke $definition $arguments $site);
  }
  return pending;
}
// A sum body pattern does not implicitly expand this pending call.
```

Pending canonical form is `macro-invoke(T,args capture(A) capture(B),site)`
(or the current helper marker before compiler conversion). Invocation recognition
returns A/B and the snapshotted T. Reconstruction returns the same pending
application, without evaluating it. The body pattern `E(+ H0 H1)` fails on that
node. Explicit compiler expansion yields `E(+ A B)`; body recognition now
returns A/B and reconstruction is alpha-equivalent expanded code. A different
macro with the same name after redefinition does not satisfy exact
invocation-definition matching. A computed macro's output is not invertible
merely because its invocation is matchable.

### 9. A useful multi-step source transformation

Use a structural Statement template to convert a direct return into an
explicit once-evaluated value plus auditing, inside a function returning int:

```x2c
macro Statement $returned(Expr $value) { return $value; }
macro Statement $audited(Expr $value) {
  int saved = $value;
  audit(saved);
  return saved;
}
meta static List add_audit(List statement) {
  Macro returned = $returned, audited = $audited;
  match (statement) {
    case returned(?value): return audited(value);
  }
  return statement;
}
```

Stages: capture the statement in the function's binding context; adapt it to
a singleton `seq` and project the inferred return-context field; recognize
`return price + tax;`; obtain `{value=E(+ F(price) F(tax))}`; construct
`D(L0:int,Hvalue), call F(audit)(R(L0)), return R(L0)`; ordinary insertion
freshens L0 and binds. Reconstructed output is `int fresh = price + tax;
audit(fresh); return fresh;`. The value evaluates once, before audit, and the
function returns that stored value even if audit mutates unrelated state.
`return;`, a `break`, or an expression from another function's dead binding
domain fails/does not transform. An outer local also named `saved` does not
capture the introduced reference. Passing a non-int-returning context is not
this transform's contract: select another output template using carried Type
information, or let ordinary binding reject incompatible output. The audit
call intentionally changes behavior; no general optimizer equivalence is
claimed. This example is specified, not executed as a production feature.

## Roundtrip properties and tested coverage

For complete structural templates with recoverable holes, let M(T,S) return
logical captures plus local correspondence, and C(T,B) construct code.

1. **Construction -> recognition:** M(T,C(T,B)) succeeds and recovers B modulo
   capture-private alpha renaming, at the same selected stage. Requires no
   lossy computation slots, coherent projections and an admissible binding
   context. Unused/unobservable holes are exempt and remain absent.
2. **Recognition -> reconstruction:** C(T,M(T,S)) is alpha-equivalent to
   S under rigid external identities and the explicit boundary map. With no
   owned declarations and no ignored metadata it is structural equality.
3. **Ordinary binding:** inserting reconstructed code into the corresponding
   admissible scope preserves reference-to-declaration incidence and rigid
   frees, and derives ordinary types. Equality is not compiler ID equality;
   fresh IDs/labels/origin differ. Contextual conversion may differ if moved
   to a different type/return context, so that is outside the property.
4. **Wire roundtrip:** descriptor/capture data retains content, holes and
   repeated reference records. It does not preserve native addresses or
   automatically extend the lifetime of a compiler binding domain.
5. **Nested composition:** constructing an inlined structural composition is
   alpha-equivalent to constructing child then parent, with explicit slot
   rebasing; effectful computation/expansion order must remain the same.

Properties 1/2 are exercised for simple canonical arithmetic and sequences by
actual x2c probes. The model exercises the alpha/boundary parts of property 2,
with supplied metadata. The cross-capture model verifies joint relocation
incidence for supplied output maps. Actual compiler property 3 is verified only for
existing macro hygiene via the existing lexical-shadow fixture, not the new
recognition pipeline. Property 4 is tested for illustrative transparent data.
Property 5 and complete contextual backtracking remain untested.

## Strong alternatives and tradeoffs

| Alternative | Concrete advantage | Concrete cost/counterexample | Recommendation |
| --- | --- | --- | --- |
| Existing IDs plus template/capture binding maps | reuses current locals, fresh rows, canonical binding Lists; preserves rigid free refs | needs aligned local correspondence and scoped capture remap | canonical design |
| Global positional IDs | easy fixed-tree comparison | hole-owned declarations shift positions; edits change paths; still needs reference resolution | use slots as labels, not semantic identity |
| Full de Bruijn depth/index AST | alpha equality for closed lambda-like trees is simple | all C namespaces/scope forms convert; movement requires shifting; free IDs still needed | larger than required; do not replace canonical AST |
| Contextual relation inside existing Match | retries remain correct, one structural engine | must journal relation state and cover both value and span comparisons | preferred full integration; prototype first |
| Resumable Match candidate enumeration | alpha checks stay outside engine; transparent capture results | continuation interface and retention cost; may enumerate many rejected partitions | viable fallback; no duplicated sequence search |
| Closed-subtree normalized keys | cheap ordinary equality and reusable caching | references to surrounding locals depend on current alignment | optimization for closed captures only |
| Final-sequence-only prototype | proves simpler path with existing Match and post-check | cannot establish arbitrary interior sequence semantics | isolated milestone, not final silent restriction |
| Separate authored patterns | existing `%()` patterns immediately usable | duplicates macro body, loses central duality and introduces drift | retain raw Match compatibility, not the new architecture |
| Name erasure/all identifiers wildcard | short implementation | `helper` shadow and outer/inner references match incorrectly | semantically unsound |
| Opaque handles | hides implementation | prevents body inspection/composition without fixing stage/context needs; datum probes already work | reject as default; no user decision authorized it |
| Named values only | less parser work, all core semantics possible | verbose transforms; cannot express inline captured code naturally | bootstrap sequencing option, not final scope |

## Implementation plan (production work not authorized)

1. **Retain the shared template interface at its producer.** In `src/macros.x`
   factor `_definition`, hole finalization, local/fresh correspondence and
   projection derivation so a named registration and anonymous value use the
   same result. Retain occurrence roles before macro-bind shells are removed.
   Reuse `src/ast.x` placement and binding helpers, grammar entry points in
   `parse`, `expressions`, `statements`, and `literals`. Preserve literal payloads
   and current inference/diagnostics. Begin with sum/twice/call and save/nested
   examples; no production parser fork or raw source reparsing.
2. **Expose macro values and calls.** Add an unapplied named reference
   in macro/meta expression parsing; snapshot visible definitions. Teach meta
   calls to apply a Macro value using its existing parameter interface. Put shared
   pure template/capture operations in the existing meta library surface
   (`lib/meta.x`, or one narrowly scoped included module if size warrants it).
   Construction reuses capture-row projections and `List.replace`; pending
   local maps pass to current expansion freshening. Reuse
   `Compiler.expand_macro_invocation_node` with existing caller-owned semantic
   transaction boundaries before ordinary `bind_syntax`; expansion itself does
   not begin a transaction. Do not move freshening into a second binder as a
   convenience. Keep raw AST insertion.
3. **Expose ownership/reference metadata from ordinary producers.** Extend
   existing `src/compiler.x` semantic binding facts, macro-local bookkeeping
   and ordinary parse/bind outputs only for missing declaration/scope/category
   facts required by recognition. Include value/tag namespaces and Name/member
   roles. Captured interfaces identify hole-private locals, fixed surrounding
   slots, cross-capture declaration/reference edges, and rigid frees. Reuse
   lexical capture protection in `expressions.x`; verify current stale-local
   retargeting cannot alter intended references.
   No second resolver or recursive code legality checker.
4. **Prototype shared recognition at fixed shapes first.** Derive existing
   Match patterns from that same template, ignoring only documented derived
   metadata. Lower fixed declaration IDs to capture slots; use separate hole
   occurrence slots for alpha comparison; enforce injectivity and boundaries.
   Demonstrate alpha save/nested, hole-owned prefix shifting, differently
   named locals, typed projections and roundtrip rebuilding. This milestone
   is insufficient for full interior sequence support and is not the final
   delivered feature.
5. **Resolve and implement Match retry integration.** Prototype the narrow
   contextual comparison/acceptance policy in `lib/match.x`,
   `lib/match-machine.x` and existing shared machine transaction machinery.
   Exercise repeated value and span captures, retries, rollback, mismatch
   atomicity and the explicit A/B/renamed-A counterexample. Compare resumable
   candidates if integration materially enlarges Match. Retain all existing
   ordinary Match behavior and static site contracts. Only after this evidence
   choose the final implementation; do not bolt on a committed post-check.
6. **Complete helper staging and inspection.** In `src/stage.x`,
   `src/meta-project.x`, `etc/meta-helper.x` and `_helper_result`, carry values
   through existing datum transport. Implement/probe the helper-build-to-program
   domain bridge: skeleton keys and external slots hydrate from current-domain
   template environments on existing requests. Do not cache hydrated local IDs
   across unit resets. Compare explicit template arguments as the smaller
   feasibility probe; it is not a substitute for the full reference/literal scope.
   Make result traversal stage-aware so a descriptor's nested deferred
   invocations remain inspectable until explicitly
   inserted/expanded. Consolidate `tpl-call`/helper marker/deferred invocation
   adapters where typed capture rows can be produced once. Replace repeated
   projection conversions, not merely relocate them. No new callback channel,
   address transport, or opaque result tag. Explicitly supersede the open
   opacity proposal in `plans/native-meta-execution.md:489` when implementing.
7. **Add anonymous values and source Match adapters.** Reuse the same descriptor
   constructor/body parser, typed signature and lexical capture environment.
   Settle literal terminators and `case` ambiguity with focused parser probes.
   Reuse `src/compiler.x` capture-layout lowering and `src/statements.x` Match
   parsing. Named and selected descriptor cases lower to the shared dynamic
   recognition path. Captured structural macro calls rename slots and freshen child declarations
   per insertion; prove transport and copying/lifetime examples.
8. **Finish compatibility and documentation.** Keep existing named macro calls,
   aliases/decorators, local captures, sequence argument restriction, raw AST
   builders and List Match semantics. New value/reference/case positions are
   contextual additions. Document values/stages/relations in the language and
   meta guide; update implementation map. Review the completed authored diff,
   remove duplicated projection/freshening/transport paths revealed by the
   shared implementation, then use the repository's existing publication
   validation only if future implementation is authorized for delivery.

### Bootstrap sequencing

Implement new data operations and factoring in code the checked-in bootstrap
already understands. Build an intermediate compiler with macro-value references and
recognition support before compiling compiler sources that use anonymous
literals or macro-derived source cases. Add parser recognition while compiler
implementation still uses old `%()` patterns. Then migrate selected compiler
transforms to ordinary x2c templates, regenerate authoritative derived outputs
through existing targets, and validate self-hosting through existing gates.
No hand edits to bootstrap C/H, no new recurring gate, and no expansion of
`precommit`/`sanity-check` are required. A parser transition requires explicit
intermediate probe evidence, not an assumption that the old compiler can parse
its new source.

### Focused validation, not a new process requirement

Implement focused fixtures for the worked examples and their must-fail cases;
run existing macro inference, lexical-shadow/capture, literal-binder, Name/Type,
sequence, decorator, meta-template and raw-Lisp canonical AST fixtures. Match
runtime tests cover contextual retry rollback, span equality and capture
publication. Helper tests cover domain reset, imported rebinding, descriptor
body inspection, marker-shaped data, repeated references and value/result stage
separation. Compiler roundtrips inspect generated AST reference incidence,
then execute relevant reconstructed programs. Include multiple copies of a
captured declaration-bearing region and the once-evaluated audit example.
Existing gate requirements apply to a future authorized implementation; this
plan adds no nightly task, mandatory benchmark, or recurring validation step.

## Unresolved decisions and coverage limits

- **Match integration:** phase 2 proves the relation hook in the actual Match
  engine for repeated values and final/interior spans, including rejection,
  retry and rollback using an already captured surrounding declaration.
  A further canonical data test defers obligations to an existing `!and`
  checkpoint after a later declaration capture and successfully retries.
  Compiler generation of these checkpoints remains unproved. Automatic ownership discovery
  and allocation cost remain unproved.
- **Helper binding-domain bridge:** separate helper compilation is verified
  by source. Skeleton/environment hydration is a viable no-callback design but
  partly prototyped: actual compiler-issued references survive relay,
  matching, reconstruction and unchanged cached-helper reuse while program
  IDs change. A real `$with_helper` value also passes with explicit hydration.
  Automatic skeleton registration/environment selection is still unproved.
  A complete bridge probe must cover cached helper reuse across unit
  resets, named snapshot redefinition, local free references, anonymous literals
  and explicit meta-local value captures. Source/declaration keys and when to
  supply that environment remain implementation choices requiring evidence.
- **Capture stage availability:** current typed captures are usable for shapes
  retained there; universal source-like recognition needs a producer-owned
  identity-bearing code view before transformations erase sugar. The complete
  grammar inventory for that view has not been done. Do not promise recovering
  arbitrary lowered source code from bound ASTs.
- **Surface grammar:** an isolated compiler now accepts unapplied named
  references, Macro parameter calls, descriptor-selected call-shaped cases
  and anonymous literals with one enclosing terminator. Anonymous factories,
  relay, return and application execute correctly. Dynamic interface/category
  checking and argument parsing need focused prototypes. Braced Expression
  bodies are optional and unresolved.
- **Composition/API:** descriptor/capture field names and internal slot mapping
  need an implementation-level review; semantics and ownership above are the
  recommendation, not an existing ABI.
- **Boundaries/lifetime:** same-unit helper composition is recommended. Portable
  persistence across compiler domains and arbitrary expansion-and-return to
  helper code are not designed here. Neither is necessary for transparent body
  inspection. Source diagnostics must keep existing provenance rules.
- **Computed macros:** cannot generally recognize output from a computation-only
  hole. Structural views or explicitly frozen fragments are viable alternatives;
  no universal inverse evaluator is proposed.
- **Unproven copying:** the model preserves one original hole-owned region; it
  does not implement automatic discovery/allocation for multiple independent
  fresh copies; the cross-capture model tests supplied copying maps only. Full
  source binder coverage (labels, tags, enum ordering, lambda captures, public declarations,
  protocols and lifecycle forms) remains production research/validation work.
- **Performance:** no throughput or memory comparison, full fixture suite,
  cross-platform transport, REPL persistence, ABI migration or complete
  self-hosting of the new feature was attempted. Successful bootstrap/probes
  do not establish these results.

Phase 2 continues the investigation using isolated compiler/runtime changes.
The entire feature is not yet proved complete: automatic scope metadata,
compiler-derived correspondence checkpoints, anonymous capture integration and dynamic
source-category parsing still require evidence. These are specific remaining
questions with viable alternatives, not reasons to introduce separate patterns
or opaque values. Current evidence is retained in
`.context/dual-macro-phase2/`, with a durable validation report to follow.

## Short design review

The body, slot interface and binding graph have one authoritative producer.
Construction and recognition derive from it; ordinary binding/typing retain
semantic ownership. Existing macro local maps, projections, Match plans,
replacement, helper datum transport and semantic transactions are reused.
Deletions target duplicated adapters after shared operations exist. The design
requires contextual comparison metadata because alpha-equivalence and scoped
substitution depend on real binding relationships; it does not authenticate
AST origin or validate executable code twice. Phase-2 retry and helper probes
reduce two earlier uncertainties; automatic capture discovery and integration
of the entire simple surface remain necessary before production changes
spread. No production implementation or publication occurred in this spike.
