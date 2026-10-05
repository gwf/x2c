> Status: reference
> Research snapshot, 2026-10-04, against origin/dev
> 4107b60af83a67abb4ceb058d4d327ce13e36ce7; original baseline 272ba77c.
> Gary subsequently authorized private implementation. The main synthesis
> owns the current dev refresh, binder decision, changes, and verification.
> Historical statements below describe the investigation before implementation.
> Publication and a PR remain held for Gary.

# AST idioms, ownership, and native character types

## Result and evidence boundary

Use named captures when recognizing an alternative and consuming its fields.
Use flat destructuring for a trusted fixed record, iteration for a traversal,
and the existing source-content owners for syntax whose stage must remain
canonical. Whole-node arguments remain useful when identity, rewriting, or a
second grammatical decision actually needs the whole node.

The initial survey's mixed-dispatch finding is narrower after investigation.
A head switch is not itself a defect. The migration must remove repeated
decoding without replacing specialized normalization with another generic
pass. No new grammar, validation layer, origin certificate, or traversal
framework is proposed.

This document adjudicates survey items I04-I08 and adds I11, compiler AST
ownership. It compares all callers of the named operations and the related
origin-unwrapping and character-type families. It does not classify every
selector expression in every compiler function. The repository-wide survey
inventory and remaining families are recorded in the synthesis plan.

All behavior below is established by current source, contracts, fixtures,
and Git history. No generated-output, runtime, or cost equivalence for a
proposed patch is claimed. There is no builds/0/x2c in this checkout. The
ordinary baseline build belongs to the first implementation step if a
rewrite is authorized; planning does not require a publication gate.

## Competing idioms and the synthesis

| Job | Established idioms | Adopt | Preserve |
| --- | --- | --- | --- |
| Static alternatives with branch-local fields | source match; List.match plus selectors | source match with named captures | existing arm order and accepted shape |
| Trusted, unconditional record projection | cadr/caddr; flat destructuring | short destructuring when it names several fields | a single clear selector with no repeated recognition |
| Source production recognition/rebuild | grammar macro patterns; raw List patterns; quotations | existing grammar/content helper when it expresses the same stage | raw patterns for types, binding leaves, and internal forms |
| Generic child traversal | foreach; ast rewrite macros; callbacks | current owner matching the identity contract | suffix-sharing and explicit source-order algorithms |
| Origin removal for inspection | manual while; Ast.without_origin | Ast.without_origin | strict termination classification and origin-changing emitter walks |
| Native char pointer/array classification | two exact predicates; canonicalizing predicate | one Type predicate, explicit normalization at the caller | typedef-aware String classification in Sym |
| Compiler source ownership | structural functions in ast.x and type.x | structural AST operations in ast.x | Type operations that actually inspect semantic types |

The recent quotation-adoption audit explicitly retains inspectable canonical
builders and SDK typed leaves. This plan does not reverse that decision.
An expression quotation can introduce a pending carrier and binding work;
it is not a spelling-only replacement for an already typed List.

## I04. Normalizer dispatch and repeated decoding

### Current usages and history

src/transform.x has 1,757 lines. Compiler._step spans lines 74-127, 54 lines.
Its first match captures origin, function, getindex, setindex, and slice
fields. Its switch groups the remaining heads. Compiler._finish, lines
131-147, owns sequence/matchcases/parens/block finishing. Compiler._children
uses the existing identity-preserving child rewrite owner.

The competing emitter dispatcher in src/emit.x, from line 98, shows named
field capture. It still forwards whole nodes for families whose helper owns
more grammar. Therefore the emitter is a useful example, not evidence that
every normalizer arm needs one identical treatment.

Commit 608a8ae82, September 30, introduced the current reading order and
Ast.without_origin/Ast.rewrap_origin. Commit b4bf0198fc subsequently put
steps on Compiler receivers. Commit c4e673f14a, October 2, added ordered List
handling. None establishes that replacing the normalizer is necessary.
Commit fbd466c5, October 1, documents how source match retains a constant-head
switch. Its historical instruction-count observation is not a current
measurement. It establishes a concrete trap: grouped !or heads can move
later cases into a sequential default path.

The archive/compiler-dual-macro-contract.md record explicitly retains
normalization, cleanup ancestry, and source origins in their compiler owners.
The source-consolidation research reports a corrected normalization-order
experiment after two failures. Treat that history as a warning about stage
and cleanup order, not a permanent rejection of capture-based refactoring.

### Family decisions

| Existing arm/family | Decision | Why |
| --- | --- | --- |
| at | retain complete original plus origin/inner captures | unchanged-node return and generated-origin policy need original identity |
| function/getindex/setindex/slice | retain current captured descent | caller already advances the grammatical decision |
| expr | retain complete expression pipeline | adapter/lambda rewriting and operator-spine handling need typed shell and identity |
| array/varray and map/vmap | retain public helpers initially | one tail traversal is not repeated recognition; a new forwarding helper needs a measured benefit |
| var | retain its single cadr initially | short trusted projection is already clear; exact capture would narrow permissive tail handling |
| segments | retain its family helper initially | it also reuses lone-literal caches and excludes raise details before traversing segments |
| cast/index | retain family helpers initially | each resolves its own source-pattern alternatives and preserves unchanged input |
| declare/decl | retain family helper initially | one declaration rule owns both heads and initializer conversion |
| dstrdecl/stmnt/dstrasgn | retain specialized helpers | they make new grammar decisions and preserve lambda/destructuring phase requirements |
| match | retain helper initially; captured descent is a prototype candidate | current destructuring accepts trailing fields; arm semantics remain its own rule |
| defer | exact capture is a prototype candidate | helper has one exact shape, but driver continuation must remain unchanged |
| return | retain source macro/type projection | binding return type is metadata beyond source form |
| raise | retain whole-node ordered pipeline | first rewrite changes the node before the second match; those matches are not redundant |
| if/while/do/for | retain truthy-family helper | different source forms and emitted return metadata require its own grammar |
| call | retain whole-node handoff | printf lowering can change the call before callee/argument recognition |
| op/postfix | retain whole-node plus captured children | unchanged result and distinct operator policies use both |
| cons/append | retain ordered-chain walker | suffix position, order, and temporary issuance are its algorithm |
| protocol/adopt/macrodef/literal and generic fallback | preserve current pruning/fallback | this is not a new validator for canonical Lists |

### Implementation

The settled default is to retain the current dispatcher. The initial survey
identified mixed syntax, but did not establish that its family boundaries add
unnecessary machinery. Do not add tail-taking wrappers merely to move cdr.
The definite capture improvements are I05 and I06 below.

A broader source-shaped dispatcher remains a bounded investigation candidate:

1. Compare only the match/defer family in temporary implementation work.
   Preserve _step/_finish recursion, pruning, and next != ast continuation.
   Capturing a result must not turn an existing next assignment into an early
   return that skips normalization or finishing.
2. Keep a single constant head per hot match arm. Use a wildcard-tail match
   for match's subject/cases, retaining its current trailing-field acceptance.
   Keep existing fallback for inputs that do not satisfy that capture. Defer's
   existing helper recognizes one exact field, so that case stays exact.
3. Keep whole nodes where identity or a later rewrite uses them. Do not alter
   the expression, call, raise, chain, declaration, or cleanup pipelines.
4. A later segment-tail comparison must explicitly translate the lone
   String-literal optimization to the captured tail. Preserve the same cache
   key and runtime_literals exclusion for raise details. Removing a head is
   not permission to drop that optimization or run semantic binding again.
5. Keep every public transform_* signature. Reject a prototype that adds
   forwarding wrappers without removing substantive duplicate interpretation.
   Count all templates and helpers when judging the source improvement.
6. Do not add malformed-node diagnostics or change accepted constructed
   canonical Lists. Inspect generated head dispatch before adoption; avoid
   dynamic pattern construction on the hot path.

Validation uses existing collection-literal order, constructed literal,
match, defer, lambda, and statement-expression fixtures. Compare generated
AST/C/H for representative unchanged input, repeated normalization, empty
collections, map key/value effects, deep left-leaning operator chains, and
nested cleanup. Preserve numeric diagnostic origins. A focused paired
translation cost check is appropriate for this hot dispatcher, not a new
recurring benchmark or gate. If dispatch or node visits regress, preserve
the head switch and retain only the narrower private capture changes.

## I05. Match recognition followed by positional SDK extraction

src/meta-sdk.x has 658 lines. x2c_syntax_type occupies lines 59-83;
x2c_binding_spelling occupies lines 247-268. Both recognize the shape with
anonymous captures and then read the field by position. Ast.designated,
src/ast.x:73-85, is the established captured-descent comparison.

The SDK is a public argument boundary. Its guard, known-binding lookup,
positive identity, spelling match, and fallback semantics are necessary.
The current anonymous patterns accept more than a single invented narrow
binding shape; preserve that acceptance when naming fields.

Commit c3d69a6118, September 30, arranged the current SDK functions. Commit
7ca06d23c0, October 1, added resolution of the macro-expr placeholder. That
newer repair must survive the migration. Capturing the initial type must
not cause the function to return the placeholder instead of resolving it.

Implementation:

1. Capture the expr type directly in x2c_syntax_type. Keep the original
   expression available for resolve_expression and then canonicalize the
   returned type exactly as today. Reading the resolved result's established
   type once is not duplicate recognition.
2. In identifier/bind alternatives, capture the same first nested List with
   !set and the original (*) condition; assign that capture to binding.
   Do not replace permissive nested-list patterns with a stricter binding
   record or remove binding_identity_try_parts.
3. In x2c_binding_spelling, capture the expr content satisfying the existing
   (? *) shape. Capture the nested identifier/bind List under its existing
   wildcard shape. Keep bare String handling and known-binding validation.
4. Leave x2c_* native interface names and inspectable canonical builders
   unchanged. No quotation or new shared SDK validation helper is needed.

Use existing macro-sdk-primitives, macro syntax type, expression-hole,
binding-spelling, and template-local fixtures. Cover untyped template syntax,
known/shadowed bindings, String input, and existing invalid identity/spelling
diagnostics. This is a local capture rewrite, not new public behavior.

## I06. Composite initializer recognition and extraction

src/initializers.x has 1,097 lines. Lines 33-68 include _convert_initializer
and _convert_composite. There are exactly two callers of _convert_composite:
the ordinary path and _speculate at lines 721-755. Both recognize
%(expr ? (composite ?)) and pass the complete expression; the helper obtains
items with expr.caddr().cadr().cdr().

Commits f71b1a5745 and d02030f9d3, September 30, arranged the current
optional-output and Compiler receiver forms. Commit a82f150b33 supplied the
current selector chain and empty-container handling. The quotation in the
result is a new output form; it does not imply the input must be rebound.

Synthesis: consume an initializer's item sequence once, while preserving
the distinction between ordinary declared-type conversion and speculative
native-dependent conversion. The stateful C subobject traversal remains.

Implementation:

1. Change _convert_composite's first data parameter from the expr shell to
   items. Delete the selector chain. Leave its other arguments and native_used
   optional output in place; they represent real alternative context.
2. At both callers, use a source match that captures the composite payload
   under the existing expr/composite predicate, then passes payload.cdr as
   items. This retains the existing payload acceptance and removes repeated
   multi-level extraction. A more exact source_composite_content(*items)
   pattern is acceptable only after confirming all producer/caller shapes;
   do not quietly add a new input restriction as a style migration.
3. Keep _speculate's transaction/DiagnosticsHold/recovery_depth bracket,
   literal and adapter rollback, type argument, condition, and catch intact.
   Use branch control flow instead of retaining a match-boolean ternary.
4. Keep empty Map/Array freshness, excess C warning handling, native targets,
   field order, and the existing typed quotation unchanged.

Use initializer-canonical, initializer-nested-native, initializer-symbolic,
initializer-native-identity, initializer-input-values, conditional-type-
initializer, and composite-string-elements fixtures. Check nested braces,
empty containers, anonymous fields, designated initializers, native-only
dimensions, rejected alternatives, and unchanged warning/source-location
behavior. Compare generated results before updating any expectations.

## I07. Origin stripping, propagation, and strict classification

The complete family has five relevant implementations:

| Operation | Location | Contract and decision |
| --- | --- | --- |
| shared stripping | ast.x:153-161, 9 lines | adopt for inspection-only consumers |
| field type stripping | type.x:144-152, 9 lines | replace local while; keep original field for _from_ast |
| field order stripping | symbols.x:1190-1200, 11 lines | replace local while before c-assert/binding inspection |
| local-static emission | emit.x:337 onward | retain walk: it updates e.origin at each wrapper |
| strict nonreturning unwrap | ast.x:193-203, 11 lines | retain checks: malformed anchors return NULL instead of proving termination |

The field-type loop predates the shared helper: 1ddbf34393, September 29,
versus helper introduction 608a8ae82, September 30. The field-order loop
was introduced in 1ee161f5ea, September 30. This is a grounded backward
adoption of a later shared operation. The change does not remove origin
storage or rewrapping from other compiler phases.

Replace only the two inspection loops with Ast.without_origin. Do not strip
the value subsequently sent to _from_ast: it currently uses field, not the
temporary declaration. Keep c-assert skipping and field source order.
Do not merge _unwrap_origin into the permissive helper or replace the
emitter's origin-changing loop with it.

Use static-assert-in-aggregate, initializer/anonymous-field, local-static,
and statement-expression-destructure-origin fixtures. Include nested valid
anchors in an inert focused comparison when existing fixtures do not cover
them. Existing malformed termination inputs must remain conservative.

## I08. Native character shape versus String identity

### Full family and the actual inconsistency

| Operation | Location | Existing semantics |
| --- | --- | --- |
| _type_is_char_pointer_like | expressions.x:3279-3283 | exact pointer/dim plus char or const char, no normalization |
| Walk.copies | regions.x:1382-1389 | repeats those exact patterns when destination is Var |
| _raw_string_type | transform.x:1587-1590 | canonicalizes first, then pointer/dim plus char |
| Sym.is_string_type | symbols.x:1144-1145 | typedef-aware canonical String identity, not any C char pointer |
| _expr_is_raw_string_literal | expressions.x:3265-3277 | literal provenance plus grouped/conditional syntax |
| _raw_string_to_string | expressions.x:3304 onward | literal caching versus dynamic String_new; evaluation structure |

Type.canonicalize, type.x:438-463, removes qualifiers. Therefore the first
survey's statement that transform accepts only char was incomplete: const
char reaches char after canonicalization. Nevertheless transform accepts
other canonicalized qualifier arrangements that the exact predicate need
not accept. A universally canonicalizing predicate would change the
expression and region consumers. A typedef-resolving Sym predicate would
also change accepted input. Neither change is authorized.

The current first helper spelling comes from e064e39543, September 30,
and the inline region duplication from 0ce7de6403 the same day. The
normalizer's canonicalizing policy predates those reading-order changes.
This is a shared representation fact with caller-specific normalization,
not evidence that the newest predicate's acceptance supersedes all others.

### Implementation

Add Type.is_char_pointer_like in the native type-predicate section. It
performs exactly the two current expressions.x patterns and returns false
for NULL. It does not canonicalize, resolve typedefs, prove NUL termination,
inspect values, or promote expressions.

Use it directly in expressions.x and Walk.copies. Delete the expression
free helper and duplicate region patterns. In transform.x use
type.canonicalize().is_char_pointer_like() and delete _raw_string_type.
After qualifier removal the const alternative adds no accepted form there.
Keep Sym.is_string_type and both literal/conversion operations unchanged.

Acceptance is a truth-table comparison, not a new language policy:

| Input | Exact expression/region predicate | Normalizer predicate |
| --- | --- | --- |
| NULL | false | false |
| (* char), ((dim N) char) | true | true |
| (* const char), ((dim N) const char) | true | true after qualifier removal |
| other qualifier layouts currently stripped to the accepted form | preserve existing exact result | preserve existing canonical result |
| (* unsigned char), (* signed char), char, nested char pointer | false | false |
| typedef name or canonical String name | false here | false here; Sym owns String identity |

Use existing string-add-lowering, conditional-string-arms,
constructed-string-addition, promoted-string-cache, region-escapes, and
region-number-values fixtures. An inert Type-level comparison should cover
the truth table and qualifier permutations without changing checked-in
expectations. Preserve raw literal caching and exactly-once effects.

## I11. Structural AST operations located in semantic type ownership

The competing conventions are Ast.method and exported ast_* functions.
Some flat functions receive arbitrary Var input, or express relationships
between several values; dotted syntax is not automatically better.

type.x:217-245 (29 lines) holds ast_prototype_declarator and its private
_prototype_params. type.x:831-879 holds the mutually recursive addressed,
direct, and indirect identifier family. Those functions inspect AST forms,
binding spellings, and source macros. They do not require a Sym or semantic
Type operation. Ast.designated and Ast.lvalue_binding already live in ast.x.

Consumers of the prototype operation are generate.x:365 and 1182. The name
family is used by cleanup.x at its call/write/escape sites. Other flat AST
operations have consumers in compiler, meta-group, generate, callables,
cleanup, and transform. The current operation names also appear in generated
compiler API documentation; relocation needs generated-doc review.

Preferred first change: move these two connected structural families to
ast.x without renaming exported functions. Preserve mutual recursion and
the private prototype helper. Keep Type.declaration_ast/parameter_ast and
type_from_ast in type.x because they cross semantic Type representations.

The prototype rule ignores top-level parameter volatile in declarations
while preserving definition semantics. It comes from the cleanup design
recorded in 68eea0aea and its consumers' later separation in 1b2acd3a1.
Do not simplify the qualifier rule during relocation.

Then apply the naming policy in the boundary plan. Do not add aliases or
forwarding wrappers solely to give these functions dot syntax. If renaming
the compiler-internal family is selected there, migrate all tracked source,
book references, and generated owner declarations together. User-facing
runtime compatibility is a different requirement.

Use existing cleanup/volatile, function-prototype, and declared-field
fixtures plus stage self-host comparison. Preserve pointer designation:
an array subobject can name the same aggregate; *pointer and pointer[index]
name storage through a holder and must not become direct-object identities.

## Delivery, dependencies, and existing plans

The immediate source-contract rewrites are I05, I06, I07, and I08. I11 can
follow them as a separate ownership change. I04 retains the dispatcher by
default; its optional comparison needs generated dispatch and normalization-
order evidence before any broader adoption.

Coordinate with active post-integration literal-normalization, optional-
reference, qualifier, and source-location work. Refresh those exact sites
on the implementation base. Preserve their final intended behavior; do not
restore obsolete pre-fix structure to obtain textual agreement with this
baseline. The quotation-adoption plan owns any syntax capability work.

For authorized implementation: build the fresh checkout as prescribed,
perform the existing relevant focused checks, inspect the authored diff,
then use the existing publication gate on the final coherent tree. Do not
run all broad gate components independently or add a new recurring check.
Planning documents remain local in this task; no publication is requested.

## Re-evaluation after the dev pull

The checkout now contains 4107b60a. Compare 272ba77c..4107b60a, not just
its last integration commit. The proposed owners in ast.x, type.x,
meta-sdk.x, initializers.x, symbols.x, regions.x, transform.x, and emit.x
are unchanged. expressions.x gained one line before the studied functions;
its char predicate now starts at 3279. All I04-I08 and I11 decisions remain.
Generate's prototype consumers moved to lines 365 and 1182.

The new compiler field macros supply a concrete composition example.
src/fields.xmacro:3-24 constructs assignment statements with source
quotations and expands a Name sequence. The compiler uses $copy_fields for
shared state and $set_fields for fresh tables and queues. $set_fields
explicitly evaluates its value once per field, preserving distinct fresh
Maps and Arrays; it is not one value copied to every destination. Do not
apply a field-list replacement to ordered normalization, speculative
initializer conversion, or AST interpretation merely because all assign
several values. Those operations need their current identity and algorithm.

Whole-statement meta calls now bind returned code at statement or block-item
position. Compiler.evaluate_meta_statement in meta-native.x:195 and
Compiler.bind_macro_lisp_statement in macros.x:3938 reuse ordinary binding.
statements.x:84 preserves the invocation token and actual position. This
permits a Stmt arrow helper returning a quoted statement without another
runtime dispatcher. It does not make canonical typed input interchangeable
with unbound syntax. Outside expansions, arbitrary data Lists still remain
runtime values; use a quotation when returning statement code there.

Typed quotation fixes now lift expression sequence scalars, accept a Name
hole supplied by x2c_ident for declaration names, and diagnose Symbol spellings
where a nonkeyword type name must be a String. Macro.declared and
Macro.inserted_items in lib/macro-value.x:126-134 own these projections.
Typed syntax still trusts its declared expression type and does not resolve
its inner expressions. Nested typed quotations use an explicit expression
hole. Preserve these current producer contracts in I05/I06; do not duplicate
the new type-name check in their consumers. Inspect the refreshed existing
macro-quotation-type-values, macro-quotation-typed-values,
macro-quotation-typed-nested, macro-quotation-scalar-splice,
macro-stmt-arrow-invocation, and meta-statement-ordinary fixtures when a
selected rewrite affects these boundaries.

The public object header repair changes generate.x, not the prototype
qualifier algorithm in type.x. Partition.object_header at generate.x:451
shares the qualifier rule for tagged and ordinary objects. I11 remains a
structural relocation only: retain that owner and public object placement,
including runtime initializer const removal and explicit privacy. The
header-object-after-function fixture already covers these boundaries.

Merged-preprocessor source positions now use line markers and
Compiler.token_source in diagnostics.x. I07 inspects AST origin wrappers;
it must not absorb or replace this separate token/source-position owner.

These conclusions were checked against source diffs, callers, book changes,
and fixture contents. No fresh compiler, generated-output comparison, fixture
execution, or timing measurement was performed in this refresh. New shipped
examples strengthen the composition plan; they do not validate its unbuilt
candidate rewrites.

## Plan review

The parser/resolver establish canonical node forms; binding identities
establish semantic name identity; Type.canonicalize establishes its qualifier
policy; the normalizer establishes stage and sequence/cleanup order. The
design trusts those facts and preserves existing SDK public-boundary checks.

It reuses Match captures, Ast origin operations, source-content helpers,
Type normalization, and current semantic lowering operations. It deletes
duplicate field extraction, two inspection loops, repeated character shape
patterns, and misplaced structural ownership. New private tail-taking steps
exist only to let callers supply facts they already captured; they do not
introduce state, caches, or another traversal. The new Type predicate owns
one genuinely shared representation fact.

The proposed source uses existing x2c syntax and representations. It retains
algorithms whose identity, traversal, origin, and stage contracts differ.
No new validator, dedicated diagnostic, or negative fixture is proposed.
Existing negative fixtures preserve current public behavior. Source review
and correction precede final publication validation in each implementation
batch; this is the current repository workflow, not an added gate.
