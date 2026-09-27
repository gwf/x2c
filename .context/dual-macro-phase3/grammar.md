# Canonical AST production inventory and projection decisions

Read-only survey at baseline 1b23aaa7e103461c3b219b9e10546aeb35384b60, using
dual-parser sources plus explicitly isolated prototype changes. The requested
`.context/dual-macro-compiler-opportunities.md` is absent in root and worker
context inventories. Parent then located it at
`/Users/gary/Git/x2c/.claude/worktrees/x2c-pythonic-syntax-spike-07ba2e/.context/dual-macro-compiler-opportunities.md`.
I read that exact survey and verified the opportunity sites below against this
baseline. Its earlier heading records a different 553429f tree; its source
line offsets are not independently authoritative for this baseline. No plans
were edited.

## Ownership and grammar facts

There is no closed AST sum type or standalone grammar in `src/ast.x`.
`Ast` is canonical immutable `List` (`ast.x:9-13`); `AstPos` lists legal parsing
and binding positions (`ast.x:16-24`). Fixed shapes are direct Lists. The
ordinary bind_syntax structural cases own constructed syntax placement and
rebind declarations, references and statements; the implementation explicitly
rejects a second validation pass and trusts established binding identities and
expression types (`parse.x:2454-2466`). The book confirms canonical parsed,
typed List ASTs, opaque numeric binding identities, source wrappers removed
for macro-visible syntax, and no recursive annotation/origin authentication
(`docs/src/reference/language.md:1872-1890`). Therefore the table below is an
inventory of owner productions, not a second AST language or validator.

A template is a parsed source form, not an emitter IR constructor. Construction
runs its existing ordinary binding/typing/lowering owners. Recognition needs a
stage-explicit projection of the same parsed body and subject. Raw `%()` remains
ordinary structural access for productions without source grammar; public
source syntax need not be invented merely to make every IR tag pretty.

## Source-facing families

| Production family / representative grammar | Source and derived fields | Authoritative owners / policy |
| --- | --- | --- |
| `(expr TYPE CONTENT)`; ident, literal, op/postfix, call/args, parens, cast/decl, sizeof, offsetof, index/slice, generic/association, va-arg | CONTENT has source grammar; outer TYPE is resolver annotation. Literal kind/type and literal payload are not all expendable annotations. Cast target declarations and sizeof Type syntax are operands. | expressions.x:2039-2094, 2153-2231, 2393-2440; emit.x:1077-1138. Public ordinary Expr templates. Wildcard only derived outer Expr TYPE at parsed/bound-recognition stage; retain explicit Type operands and literal structure. |
| `(declare BASE (bindings (bind NAME MODIFIERS)...))`, typedef, decl; initializer `(op = bind value)`; `(param BASE bind)`, fnmod/params, dim | BASE/modifiers carry user-written declaration/type syntax. NAME starts spelling or existing binding and ordinary owner publishes identity. fnmod list is declarator grammar, not a parallel Type language. | parse.x:2601-2637, 2675-2716; emit.x:1208-1228. Public declaration/function/field/parameter templates. Never ignore declaration Type just because outer Expr types are projected. |
| `(function RTYPE DECLARATOR BODY)`; struct/union/fields; enum members; named-type | Source syntax including qualifiers, fields and declarators; references can become canonical bindings. NamedType expands through ordinary declaration publication. | parse.x:2491-2504, 2675-2730; emit.x:1210-1222; language.md:1892-1906. Public existing grammar categories, no new IR spelling. |
| `(stmnt E)`, empty, return, if/while/do/for/switch, case/default, break/continue, goto/label, `(block ITEMS...)` | Source structure. Parsed `(return RETURN_CONTEXT E)` carries derived expected result type; transformed `(return E)` does not. Block opens lexical scope; group and seq do not necessarily do so. | statements.x:125-240, 434, 514-525; parse.x:2744-2819, 2889-2913; transform.x:3068-3073. Public Statement/block templates; compare return operand, not derived context. Preserve block/scope distinctions. |
| seq/group; preproc; protocol/adopt/macrodef | seq is placement/splice aggregate; source compile-time items retain source-order semantic effects. Macrodef is transparent descriptor fields, not executable function syntax. | parse.x:2558-2571, 2717-2735; macros.x:3370-3390; emit.x:1203, 1233. Public existing category source where present; raw Lists useful for descriptor inspection. |
| lambda `(lambda PARAMS [(captures ...)] BODY)` | Existing source lambda syntax; capture data/typed representation partly derived. | expressions.x:2199-2205, 2770; transform.x:4240-4242. Public lambda templates at supported syntax stage; no demand to construct lowered closure layout using lambda source. |
| array/map/segments; composite/commas; dotinit/indexinit; destructuring dstrdecl/dstrasgn | Literal, interpolated-string, designated-initializer and destructuring source grammar with resolver annotations. | expressions.x:715-812, 2041-2045, 2098-2175, 2685; transform.x:3048-3067, 3528-3551. Use existing ordinary syntax before lowering, not new AST keywords. |
| try/catchcases/raise/defer; match and source case rows | Existing source grammar. Handler handles/capture declarations and case guard control wrappers are derived; pattern data inside a source Match is not automatically syntax-template metavariable grammar. | statements.x:330-375, 462-490; parse.x:2820-2888; transform.x:3076-3088, 3755-3829. Public source templates retain patterns as pattern data; normalize their compiler scaffolding only at an explicit stage. |

## Lowered or administrative productions: individual decisions

| Production | Existing producer / consumer | Recommendation |
| --- | --- | --- |
| `(cache ID)` | compiler.x:2248-2254, 2275-2326; stage.x:119-136; emit.x:1082. ID indexes compiler-owned constant graph, not syntax binding. | Permanent raw `%()` exception for compiler internals. Public source literal template already covers value creation. Matching requires owner cache context or projecting its actual constant, never comparing unrelated cache IDs as code identity. |
| `(localinit DECLARATION BODY)` | transform.x:2037-2057 inserts runtime static initialization region; emitter dispatch emit.x:1059. | Permanent raw exception for lowered stage. Source `static T name = value;` and block template owns public behavior; no new region keyword. Must not simply erase wrapper because entry/jump semantics matter. |
| `(sourceinit FUNCTION)` | cache.x:451-468 generates file-static initialization helper; emit.x:1060-1061. | Permanent raw exception. Source file-static declaration remains user surface. It has source-placement/order semantics; recognition cannot treat generated helper as the original declaration without an explicit inverse/owner projection. |
| `(guarded BODY)` in a Match case | statements.x:368-373 inserts guard-dependent break marker; parse.x:2877-2881; emit.x:586 removes marker to choose arm flow. | Raw exception for exact case-control IR; public `case PATTERN if (condition):` already exists. Source template should use guard syntax, not new guarded keyword. Do not erase in lowered recognition: fallthrough/retry distinction matters. |
| `(tadapt TARGET SOURCE)` -> `(expr TARGET (tadapt ORIGIN SOURCE))` | etc/builtin-macros.xmacro:12 constructs `$adapt`; expressions.x:2420-2437 resolves; transform.x:165-255 emits typed helper. | Not wholly lowered-only: use existing `$adapt` public macro for source construction/recognition; retain raw exception for resolved origin/helper details. Definition/invocation stages must be explicit. No duplicate adapter syntax or validator. |
| `(matchcases SUBJECT (BINDERS PATTERN BODY)...)` | transform.x:3076-3088; emit.x:1237. | Raw lowered exception; public `match` source form owns code. Derived BINDERS should come from existing MatchCaptureLayout, never a second capture analyzer. |
| `(varray ...)`, `(vmap (vpair ...)...)` | transform.x:3528-3551 lowers array/map elements to Var; emit.x:1033-1041. | Raw lowered exception; public []/{} literal grammar. These are not source-preserving aliases if conversion calls or ordering changed. |
| `(initval [input ...] (CONDITION PATH DESTINATION EXPRESSION)...)`, initcode | expressions.x:3922-4003 produces initializer alternatives; ast.x:241-249; cache.x:265; emit.x:759-764, 1057-1062. | Raw exception for alternative tables/emission macros. Public source expressions/initializers remain templates; exact derived initializer decisions require compiler context. Do not invent a new public conditional-init grammar. |
| `(managed-init INITIALIZER)` | expressions.x:2059-2062; parse.x:2593-2597; transform.x:4125. | Raw marker exception; source initialization/ownership constructs continue through ordinary owners. Not a freely ignorable grouping. |
| lowered `(defer BODY ENV CALLBACK RECORDS WRITTEN)` | transform.x:3755-3818; original unary defer source becomes callable region. | Raw lowered exception; use existing unary `defer statement` publicly. Generated environment/callback identities are compiler facts, not user holes by default. |
| `(var E)`, cons/append/string/nil, c-assert | compiler.x:2275-2326 caches literal graphs; transform.x:4250-4253 converts; emit.x:1042-1056. Some source List literal/Lisp construction lowers through these. | Raw internal exact-form access remains useful. Source ordinary literal/append/assertion machinery is sufficient; do not create one new public AST constructor per backend convenience. |
| src, at, api-source, binding | macros.x:3778-3820 captures source; ast.x:33-65 identities; parse.x:2477-2489, 2738-2743; emit.x:1024. | Keep ordinary canonical metadata accessible but no new source wrapper syntax. Recognition compares an origin-insensitive view while returning original captures; identities retain compiler ownership. Binding is semantic content, not removable metadata. |
| declaration-bundle, declaration/syntax-recipe, declaration-pending/forward/default/function | parse.x:2505-2557, 2675-2716 retains once-only shallow declaration production; compiler.x:1302 onward. | Raw phase/administrative exception, preserving source-order/lifetime semantics. Public Declaration/NamedType and existing macros own surface. Matching cannot rerun arbitrary recipes backwards. |
| macro-invoke, macro-slot, macro-bind, meta-call/meta-cap, tpl-call | macros.x:2924-2963, 3011-3029, 3971-3985, 4247-4270; expressions.x:2071-2089. | Existing canonical stage records. Public named/anonymous template and invocation forms should generate them. Raw List inspection stays allowed; only structural template callees compose bidirectionally. No inverse of arbitrary meta computation. |

“Permanent raw exception” means retaining `%()` as normal expressive structural
access for that compiler production, not hiding it behind opaque objects,
authenticating producer origin, or denying ordinary legal constructed Lists.
A new public source form requires its own user semantics; merely eliminating
a raw internal AST match is not sufficient reason.

## Mixed Name: concrete recommendation and unresolved edge

Current `_parse_argument` returns a String Name spelling, except a visible
local of a template can pass its canonical binding (`macros.x:3833-3852`).
`_capture_row` derives source/value/expression/splice projections
(`macros.x:2994-3009`). Member substitution intentionally uses captured source
spelling, consulting `semantic_binding_facts[(source-spelling BINDING)]`
(`macros.x:3927-3948`). Member-hole parser emits a distinct `member` projection
(`macros.x:3951-3963`). Thus a single raw Match binder substituted into every
projection is semantically wrong: canonical binding, expression ident, member
spelling and splice List have different roles.

Recommended logical Name capture is the existing value projection: String for
an unbound/member-only name, canonical binding for a declaration/reference
identity. Construction derives expression/member/splice through existing
capture-row/member-binding owners. Recognition gathers constraints from each
projection: declaration/reference occurrences must denote the same candidate
binder; member occurrences compare the Name source-spelling projection; repeated
member occurrences compare the same spelling. Alpha matching permits a local
candidate binder to have a different user label while preserving its references;
a member field remains a member spelling, not a lexical variable renamed by
alpha normalization. A mixed Name hole has an explicit spelling relation to
that field, independent of program binding identity.

An introduced template binder passed to member position can have a fresh emitted
spelling but an original source-spelling fact. Using binding_identity_spelling
alone instead of the existing source-spelling fact changes established behavior.
Recognition from transported bound syntax therefore requires its existing
binding/spelling capture projections or ordinary compiler context. It must not
recover local semantic identity by matching spelling alone. Member-only Name
captures remain context-free structural recognition.

Phase3 capture probes verify repeated member Names (hit1/miss0), member
reconstruction and Type/Statement logical interfaces. They do not verify a
single hole spanning declaration, reference and member roles. Binding worker
proves real source local alpha relationships; it does not close this Name
projection contract. Implementing this should extend existing capture rows and
relation constraints, not introduce a new AST representation or Name validator.

## Source positions: comparison versus returned captures

`at` origin IDs are compiler-context diagnostic anchors. `src` stores one
complete source argument/target range; the SDK source registry keys the actual
captured syntax value identity (`macros.x:2302-2308, 430-453, 3778-3820`).
The book explicitly denies source text to arbitrary equal AST Lists
(language.md:1880-1884). Structural equality is therefore not proof of source
range ownership, and a reconstructed or normalized capture must not fabricate
an exact source range by copying numeric anchors.

Phase3 hygiene removed at/src symmetrically for structural comparison and
proved canonical binding identity preservation. Its returned normalized
subtrees may lose their exact original wrappers. Optional origin-wrapper Match
alternatives exceeded existing Match code4096 limits; that failed implementation
is not evidence against preserving source positions by other designs.

Recommendation: keep original subject as the capture/reconstruction carrier;
comparison traversal projects at/src out while retaining path-to-original
subtree correspondence. Relation checks use projected equality, returned values
use original captures when they exist. Newly constructed output inherits ordinary
macro expansion definition/invocation/generated ancestry, not invented source
text. Exact substring text for a discovered interior capture is a separate
capability: existing complete argument/target source records do not guarantee
per-node exact spans. That policy is unresolved and should be stated honestly.
This per-attempt comparison/capture correspondence is not origin authentication
of constructed syntax and does not justify a new semantic validator.

## Coverage limits

This is a focused grammar/ownership inventory, not exhaustive enumeration of
every helper-produced List. Protocol registry rows, collection/cache metadata,
project/native helper wire manifests and region-analysis summaries are not AST
productions merely because they are Lists; they were not inventoried as AST.
No public syntax implementation, phase/corpus changes or bootstrap edits were
made. Low-level emitted C token Lists are outside syntax template recognition.


## Corrections and usable compiler opportunities from the located survey

The broad source-template opportunity is sound: `_callback_function`
(transform.x:139-162), `_build_func_adapter` (transform.x:420 onward),
`_defer_block` (transform.x:2288-2320), `_catch_arms` (2331-2353),
`_try_block` (2354-2417) and `_resolve_func_call`/`_func_call_arguments`
(expressions.x:1592-1738) construct source-bearing skeletons with raw Lists.
Type conversions, region bookkeeping, variable-length preparation loops and
helper-registration side effects remain their ordinary compiler owners.
Only skeleton spelling is a dual-template candidate; wrappers that only
rename the old raw AST walker would not deliver the survey's simplification.

### Wrapper parameter grammar already exists

The survey's need for a new `Params` hole kind or a sequence of `Decl` is
incorrect at this baseline. `author_kinds` already accepts `param`
(macros.x:3059-3062); `_parse_argument` owns Param parsing
(macros.x:3828); `parse_parameter_list` calls the same template slot parser in
parameter position (parse.x:916-925). `_kind_accepts_role` does not accept
Decl as Param (macros.x:3073-3083). New `Params` public syntax is unnecessary.
Use `Param $parameters...` and place the sequence at the end of the macro
parameter interface: `_invocation_arguments` greedily parses its comma tail
(macros.x:3874-3881), so a sequence before later supplied arguments cannot be
assumed to work.

Actual parser/compiler executable `grammar-param-sequence.x` passes, expanding
`$forward(int, forwarded, twice, 3, int x, int y)` to a wrapper that calls the
ordinary function and executes 6. The source skeleton is:

```x2c
macro Unit $forward(Type $result, Name $name, Expr $target,
  Expr $arguments, Param $parameters...) {
  static $result $name($parameters...) { return $target($arguments); }
}
```

`grammar-decl-as-parameters-fails.x` changes only Param to Decl and fails with
`macro hole 'parameters' has ambiguous kind; first: Decl also: Type` at the
function parameter slot. That rejects this concrete Decl substitution, not
all alternative parameter designs. Multiple forwarded call operands can be a
single captured Expr commas/args producer or a canonical argument sequence
passed as data to the descriptor; two greedy source sequences require an
explicit interface design. Empty parameter sequences must reconstruct the
ordinary `(void)` convention where appropriate, not assume C empty parameter
list semantics (`parse.x:934-939`; transform.x:60-69).

### Region Name input must preserve its issued identity

`_region_binding` already calls `sym.introduce(fresh_name(role))`
(transform.x:1690-1694). The current `_try_block` receives that frame identity,
uses it in its declaration and every address/member reference, and surrounding
region exit machinery also carries it. A template migration must take it as
an explicit Name input and preserve that exact identity, rather than introduce
an additional literal frame declaration that freshens independently.

This uses existing behavior: ordinary `_install_declarator_node` accepts an
existing binding List and binds the same identity when needed
(parse.x:2326-2332). Macro freshening iterates only the definition's introduced
`fresh` rows; explicit Name inputs are supplied capture projections and are
not freshened again (macros.x:4067-4085). `frame.env` member projection uses
the existing source-spelling path where relevant. Byte-identical compiler
lowering is a stronger compatibility goal than program alpha equivalence here:
passing existing compiler-issued identities avoids needless regenerated names,
registrations and emitted deltas.

### Open templates need a deliberate free-reference policy

The located survey proposes “every free name implicitly x2c.ident” or an
open/closed knob. Current closed macro behavior and phase3 main/helper hydration
do not establish that new public policy. Existing compiler skeletons often use
raw String callees (`_catch_call`, transform.x:2323-2324) and target-unit global
lookup (`_adapter_helper`, transform.x:318), so compiler source templates need
explicit target-context references, supplied callee/type Name or Expr inputs,
or a deliberately approved insertion-resolution mode. Supplying typed inputs
can prove a first migration without silently changing definition-site behavior
for ordinary macros. An implicit “inside compiler means open” rule introduces
semantic context dependence and should not be inferred from prototype success.


## Mixed Name working bounded constraint probe

`grammar-mixed-name.x` / `.log` exit0: output `mixed Name 1 0 1 0`.
Actual named macro `$named(Name $name, Expr $object)` constructs `int $name=1;
$name += $object.$name;`. A Statement source producer captures the enclosing
block through the native helper, then a private recognizer uses ordinary Match
binder equality on declaration and reference plus existing
`x2c_binding_spelling` to constrain the member spelling.

`$named(value,obj)` hits; handwritten `value += obj.other` misses the member
constraint; `$named(other,obj)` hits, demonstrating differently labelled
logical Name inputs; `int other=1; value += obj.other` (where value is the outer local) misses the repeated
program-binder equality even though the member constraint for other would pass.
No numeric binding was authored; the log shows main-issued canonical bindings and ordinary objects. These IDs are incidental diagnostics, never
requirements of the recognizer.

This demonstrates a viable role-specific Name constraint using existing
producer operations. It does **not** implement universal `case template(?name)`
projection synthesis or show that all Name roles normalize automatically. It
uses binding spelling, so source-spelling differences caused by introduced
fresh locals remain the separate current compiler fact requirement above.

## Expanded field inventory

`grammar-fields.md` enumerates canonical source/derived positional forms with
S/D on every described field; `grammar-head-census.md` records all 215 literal
head spellings detected in the bounded AST owner file set, distinguishing
metadata and presentation output. This is much stronger than a representative
family table, but is not a mechanically established proof of every accepted
constructed List: dynamic heads, String leaves and generic C-token emitter
fallback deliberately make the AST contract open. No second validator grammar
or serialized AST type has been introduced. The main remaining proof gap is
exhaustive semantic Type modifier/base alternatives across dynamic constructors
and protocol/declaration administrative subrecords; ordinary owners still
control those. Regions and helper wire metadata are explicitly not program AST.
