> Status: active
> Extensive investigation and remediation proposal, 2026-10-04.
> Re-evaluated against fetched origin/dev
> fd88fae44b419af69ca8ed55afbdcfc66f3ef943.
> Original research baseline: 272ba77c. Refreshed 2026-10-04.
> Gary authorized implementation after the binder investigation. Work stays
> on codex/idiom-synthesis-refresh in this worktree. Gary authorized commits
> and pushes only to that branch. A PR and integration into dev remain held.
> Implementation evidence appears below.

# Synthesize compiler and runtime idioms

## Result

Use one owner for each fact, one convention for each role, and the current
language's largest direct form that preserves the required stage and identity.
Uniformity should remove interpretation work from the reader. It should not
erase meaningful differences in arithmetic, storage, binding, lifetime,
diagnostics, or public interfaces.

The investigation supports immediate, bounded changes to scalar declarations,
unused generator arguments, AST capture, inspection-only origin stripping,
native character-type classification, private output references, and structural
AST ownership. Two ordinary lexical Scope brackets are adoption candidates
whose unwind behavior needs focused comparison.

It also corrects several preliminary recommendations. Keep the meta Map scalar
ledger, the Map core callbacks, compiler-native Macro identifiers, and published
pointer signatures. Keep the normalizer dispatcher by default. Investigate
larger source-template compositions through explicit bounded experiments;
do not turn a visual mismatch into permission for a new framework.

The [concrete code changes](#concrete-code-changes) section shows proposed
source excerpts, file moves, and the two larger composition experiments.

## Research records and coverage

This plan combines three subagent records and the coordinating AST/type record.
The records were saved and read back before synthesis. An independent reviewer
checked the AST plan, identifying literal-cache and permissive-tail constraints
that the coordinating plan now records. The coordinator checked representative
source claims, Git history, shared conventions, and cross-plan compatibility.

| Detailed record | Decisions owned |
| --- | --- |
| [Ledgers and callbacks](idiom-synthesis-ledgers-2026-10-04.md) | scalar declaration projection; callback catalogue comparison; Literal readers; fixed versus mutable tables; List construction |
| [Container generators](idiom-synthesis-generators-2026-10-04.md) | unused internal arguments; family interface preservation; arithmetic/absence/export policies; region-name projection |
| [AST and type operations](idiom-synthesis-ast-2026-10-04.md) | normalizer adjudication; SDK/initializer capture; origin consumers; native char predicate; structural ownership |
| [Native boundaries and borrowing](idiom-synthesis-boundaries-2026-10-04.md) | Macro naming; published versus private outputs; complete manual Scope brackets; lifecycle exceptions |

The refreshed inventory covers 154 hand-authored files, 84,548 physical lines:
63 lib .x files/30,928 lines, 23 lib .xmacro files/3,346 lines, 45 src .x
files/47,653 lines, and 23 src .xmacro files/2,621 lines. Generated lib/x2c.x
and src/linked-meta.x are excluded. Counts include comments and blanks.
The original inventory was 152 files/84,314 lines. The new selector and field
macro units account for the two added files; net authored growth is 234 lines
across the complete changed corpus, not an estimate of this plan's cost.

This second investigation evaluates the original ten findings and related
families through full usage searches, callers, producers, book contracts,
active plans, and selected introduction/change history. It follows REPL,
fixture, SDK, and native-interface consumers outside lib/src when necessary.
It is not a line-by-line semantic audit of all 84,548 lines, an external-client
survey, or a runtime performance study. Diagnostic macro catalogues remain
outside individual adjudication unless a studied family uses them.

At the investigation snapshot, no compiler build, executable rewrite probe,
runtime suite, fixture check, benchmark, or publication gate had run.
The checkout then had no builds/0/x2c.
The proposals distinguish source-established edits from designs requiring
generated-output evidence. Source line savings and speedups remain unmeasured.

## Re-evaluation after pulling dev

After Gary approved branch-only delivery, the private branch was fast-forwarded
to fetched origin/dev fd88fae4. The existing edits were reapplied without
conflicts. The intervening frontend change assigns diagnostic reporting to
the reporting compiler; none of this plan's changes replace that owner.
The new consolidated code standard remains a draft and does not replace
current guidance or add validation requirements. The implementation decisions
remain applicable. A fresh bootstrap rebuild passed after this integration.

Before implementation, the private branch was fast-forwarded again to
c5c84a5d. The intervening changes share an Array postfix template and Map
iterator step. They preserve the unused Map arguments identified in I03.
The table below retains its explicit 4107b60a research coordinates; current
implementation links and counts belong in the execution record. The local
dev branch has not been advanced by this work.

The separate b1bf worktree was fast-forwarded to fetched dev 4107b60a and is
now on codex/idiom-synthesis-refresh. The local dev branch and its checkout
were not changed by this task. The five planning documents and their index
were preserved. This refresh examines the full 272ba77c..4107b60a change,
including source, relevant book contracts, fixture contents, and linked-helper
registrations. It does not treat checked-in bootstrap output as fresh proof.

The previous 31b2d994 notice is superseded by this checkout update. Whole
statement meta calls now work in ordinary code as well as expansions, Stmt
arrow bodies can invoke Stmt macros, and typed quotation projections handle
scalar sequences and declaration Name holes. Current Type-name validation
requires Strings for nonkeyword names. These are available capabilities,
not language prerequisites for the bounded experiments. Preserve their
insertion-position and binding contracts when adopting them.

Two delivered examples now establish the starting idiom. List selectors use
source templates, Name holes, meta-computed spellings, and deferred Unit
applications. Compiler field copy/set uses quoted assignments and Name
sequences; set evaluates the value separately for every field, preserving
fresh collection identity. Reuse those patterns when the target does the
same job. Do not introduce a universal AST walker, configuration language,
or another binder to emulate them.

The larger Map comparison now starts with meta selection of complete named
source templates, rather than arbitrary statement fragments referring to
generated locals. Unit templates still own generated declarations; returned
statements retain their actual statement position. This is a concrete design
refinement, not proof that the Map candidate preserves parameter binding or
reduces total machinery. The small unused-slot rewrite stays independent.

The Pool intern table now composes the retained Map scaffold/core over a
key-only union record. It is a justified storage specialization of the same
family, not a parallel hash implementation to consolidate away. Shared Error
nonreturning causes now use a SymbolSet literal directly. These changes
strengthen the convention of using the smallest existing form suited to the
actual fact and consumer; they do not justify replacing every fixed Map.

Public object header placement and qualifier handling, package export order,
merged-preprocessor source locations, native meta linking, and nonfinite
numeric serialization also changed. Preserve those repaired producer and
boundary contracts in related work. None authorizes removing the current
SDK checks, origin-changing walks, or native signatures. The detailed records
state how each relevant repair affects its decisions and validation scope.

Regex and format catalogue names now use local reason/error categories.
Their callers changed with them while payload owners retained failure policy.
This is a naming improvement within those import boundaries; it does not
justify renaming native Macro entry points or unrelated exported interfaces.
The broader diagnostic-catalogue campaign remains with its existing plan.

No source rewrite from this plan has landed in the intervening commits.
Refresh the source links and counts rather than claiming those issue families
were resolved by the new examples. Candidate generated-output equivalence,
callback truth/storage behavior, policy binding, Scope unwind differences,
and cost comparisons still require focused implementation evidence.

## Issue register and decisions

The I01-I10 identifiers correspond to the original survey order. Additional
items expose connected opportunities or justified distinctions. Source ranges
are pinned to the baseline; implementations must search current owners.

| Issue | Files and baseline size | Mechanism / relevant span | Synthesis and disposition |
| --- | --- | --- | --- |
| I01 | [native-scalar-types.xmacro](../lib/native-scalar-types.xmacro#L21) 92; [lisp.x](../lib/lisp.x#L43) 1,913 | 14 rows and 14 access invocations, Lisp 43-56 | Rewrite declaration projection from the existing meta Map; keep exact scalar/native access policy. Correct stale signature-column prose in type.x. |
| I02 | [lisp.x](../lib/lisp.x#L1457) 1,913 | 36 wrappers/36 registrations; 1457-1549 and 1568-1608 | Bounded explicit source catalogue experiment. Generate bodies and binding rows together without another signature, truth, or lifetime model. |
| I03 | [map-generics.xmacro](../lib/map-generics.xmacro#L354) 961; [array-generics.xmacro](../lib/array-generics.xmacro#L668) 911 | Map operations 354-618; observation 691-736 | Delete unused internal slots first. Observation needs 1 of 5 arguments; operations does not use unbox. Keep original outer family forms and core callbacks. |
| I04 | [transform.x](../src/transform.x#L74) 1,757; [emit.x](../src/emit.x#L98) 1,261 | normalizer 74-127 | Narrow the finding: retain dispatcher and meaningful whole-node pipelines. A source-shaped match/defer comparison is conditional, not a wholesale rewrite order. |
| I05 | [meta-sdk.x](../src/meta-sdk.x#L59) 658; [ast.x](../src/ast.x#L153) 302 | SDK 59-85 and 247-268 | Adopt named captures under the same patterns. Preserve template-type resolution, known binding checks, and native SDK identities. |
| I06 | [initializers.x](../src/initializers.x#L33) 1,097 | conversion 33-68; speculative caller 721-755 | Capture composite payload at both callers and pass its items once. Preserve the subobject algorithm, transactions, native alternatives, and empty-container freshness. |
| I07 | [type.x](../src/type.x#L144) 976; [symbols.x](../src/symbols.x#L1190) 1,431; [ast.x](../src/ast.x#L153) 302 | type 144-152; symbols 1190-1200; ast 153-161 | Adopt Ast.without_origin for two inspection-only loops. Retain strict termination classification and origin-changing emission. |
| I08 | [expressions.x](../src/expressions.x#L3279) 3,930; [regions.x](../src/regions.x#L1382) 1,455; [transform.x](../src/transform.x#L1587) 1,757 | expressions 3279-3283; regions 1382-1389; transform 1587-1594 | Add one exact Type.is_char_pointer_like predicate. Keep normalization explicit at the transform caller and typedef-aware String identity separate. |
| I09 | [macro-value.x](../lib/macro-value.x#L67) 834 | five Macro_* native entries amid dotted operations | Retain exact names/signatures. Explain the boundary through the role convention; do not add cosmetic aliases or change method/reflection facts silently. |
| I10 | [var-unbox.xmacro](../lib/var-unbox.xmacro#L17) 31; [varops.xmacro](../lib/varops.xmacro#L47) 77 | unbox 17-20; varops 47-51 | Adopt structural Literal capture locally while preserving leaf-ledger confinement and existing compiled tag queries. |
| I11 | [type.x](../src/type.x#L217) 976; [ast.x](../src/ast.x#L153) 302 | prototype family 217-245; designated-name family 831-879 | Move structural AST families into ast.x, retaining exported flat names and algorithms. Keep semantic Type conversion in type.x. |
| I12 | [match.x](../lib/match.x#L688) 1,402; [lisp.x](../lib/lisp.x#L977) 1,913; [scan.x](../lib/scan.x#L234) 725 | four private output helpers versus published/native pointers | Adopt references in Match _first/_replace_all/_replace and Lisp _read_form. Keep native callbacks, arrays, retained addresses, public scanner and parser signatures. |
| I13 | [match-cache.x](../lib/match-cache.x#L550) 580; [meta-group.x](../src/meta-group.x#L813) 871 | constructor 550-562; reset bracket 813-818 | Adopt lexical $scope destination brackets after checking unwind restoration. Keep Error floor, Thread sealing, Context lifecycle, and existing entry decorator brackets. |
| I14 | [regions.x](../src/regions.x#L165) 1,455; [typed-array.x](../lib/typed-array.x#L1) 189; [typed-map.x](../lib/typed-map.x#L1) 356 | 11 paired typed-container conversion rows | Retain explicit effects. Defer a name projection until one ledger replaces actual declarations and makes effects explicit as well. |
| I15 | [native-scalar-types.xmacro](../lib/native-scalar-types.xmacro#L40) 92; [var-tags.xmacro](../lib/var-tags.xmacro#L267) 395 | List builders 40-43 and 267-272 | Compare current List-producing quotation forms at the cold consumers. Sequence lifting is available; canonical List insertion equivalence remains unproved. Retain builders unless the comparison preserves stage and identity. |

The detailed records give exact consumers, competing choices, implementation
steps, edge cases, and existing validation for every row. Related pointer and
Scope census results are classifications, not deletion counts.

## Concrete code changes

These excerpts show the proposed source, not just the design vocabulary.
"Current" excerpts come from 4107b60a. "Proposed" excerpts are uncompiled
illustrations of the selected edits, not tested patches. Where a function is
only partly shown, its remaining algorithm stays as described below.

### I01: generate the scalar access declarations from the existing Map

Current lisp.x manually repeats all fourteen Types from the scalar ledger:

```x2c
$native.scalar.access(char);
$native.scalar.access(signed char);
$native.scalar.access(unsigned char);
// Eleven more invocations repeat the remaining ledger keys.
```

The proposed consumer becomes one invocation:

```x2c
$native.scalar.access.all();
```

Its producer belongs beside the existing template in
native-scalar-types.xmacro. The intended shape is:

```x2c
meta static List _scalar_access_units(Macro access) {
  Array units = [];
  List rows = native_scalar_types().list().sort();
  foreach (List row, rows) {
    Type type = row.car();
    units.push(access(type));
  }
  return units.list_free();
}

macro Unit $native.scalar.access.all() {
  $_scalar_access_units($native.scalar.access)...
}
```

The existing $native.scalar.access body still creates the exact load/store
functions and access record. Its alignment builder and the generated lookup
remain. The change removes the second list of Types, not the authoritative
Map. Adding a scalar row would then produce its declaration and lookup entry
from that same row. The selector generator supplies the working Macro-value
and deferred Unit example; the scalar-specific shape still needs translation.

### I03: stop passing facts the Map helpers do not use

Current observation accepts five arguments, although its body uses only map:

```x2c
macro Unit $map.typed.observation(
  Type $map, Type $key, Type $value,
  Name $box_key, Name $box_value
) {
  // Existing compare/str/repr/write declarations and bodies.
}
```

Proposed:

```x2c
macro Unit $map.typed.observation(Type $map) {
  // The same compare/str/repr/write declarations and bodies.
}
```

The outer interface continues to accept its real boxing facts. Only the
forwarding to observation changes:

```x2c
macro Unit $map.typed.observe(Type $family, Type $key, Type $value,
  Name $box_key, Name $box_value) {
  $map.typed.observation($family);
  $map.typed.box($family, $key, $value, $box_key, $box_value);
}
```

Similarly, remove the unused Name $unbox from typed.operations and its
invocations. Keep it in typed.family, which still passes it to typed.convert.
This changes argument lists without replacing storage, hashing, callbacks,
update arithmetic, or the supported custom-family interface. PoolTable's core
composition stays intact.

### I05 and I06: name fields when their shape is recognized

Current x2c_syntax_type matches an expression, then selects its Type:

```x2c
case %(expr ? ?): {
  Type type = value.cadr();
  if (type === %(<macro-expr>))
    type = active.expander.resolve_expression(value, active.site).cadr();
  return type.canonicalize();
}
```

Proposed:

```x2c
case %(expr ?matched_type ?): {
  Type type = matched_type;
  if (type === %(<macro-expr>))
    type = active.expander.resolve_expression(value, active.site).cadr();
  return type.canonicalize();
}
```

The match names the first field, then the existing conversion assigns its
Type. Untyped capture preserves the original pattern acceptance. Native
`?(Type type)` syntax is valid, but adds a List-tag filter that this cleanup
does not require. The selector on the newly resolved expression
stays because that result is a different value. SDK guards and binding checks
remain. Other binding captures follow the same local change without narrowing
the accepted patterns.

Current initializer conversion recognizes a composite, passes the entire
expression, and then extracts its items again in the callee:

```x2c
if (value.match(%(expr ? (composite ?))))
  return c._convert_composite(
    value, type.canonicalize(), target, NULL, native_used);

// At the beginning of _convert_composite:
List items = expr.caddr().cadr().cdr();
```

Proposed ordinary caller:

```x2c
match (value)
  case %(expr ? (composite ?payload)):
    return c._convert_composite(
      payload.cdr(), type.canonicalize(), target, NULL, native_used);
return c.convert_expression(value, type.declared());
```

_convert_composite takes List items in place of List expr and deletes its
selector chain. The speculative caller captures the same payload inside its
existing try/transaction bracket and passes its own target and condition.
Empty-container freshness, subobject traversal, rollback, native alternatives,
and excess-initializer warnings stay. Before adopting the typed payload
capture, verify it accepts every legal producer shape accepted today.

### I07 and I08: reuse the exact inspection operation

Current field inspection in type.x:

```x2c
List declaration = field;
while (declaration.car() == <at>) declaration = declaration.caddr();
if (declaration.car() != <c-assert>) types.push(_from_ast(field, context));
```

Proposed:

```x2c
List declaration = Ast.without_origin(field);
if (declaration.car() != <c-assert>) types.push(_from_ast(field, context));
```

The original field still reaches _from_ast. Apply the same substitution to
symbols.x's inspection loop. Keep origin-changing emission, metadata rewrapping,
and strict termination classification in their current owners.

Move the duplicated native character-shape test into type.x:

```x2c
int Type.is_char_pointer_like(Type type) {
  if (!type) return 0;
  return type.match(%((!or (dim *) (!quote *)) char)) ||
    type.match(%((!or (dim *) (!quote *)) const char));
}
```

Expressions then calls type.is_char_pointer_like(). Walk.copies replaces its
two inline patterns with source.is_char_pointer_like(). Transform's caller
canonicalizes explicitly before calling the predicate. Keep the null guard
and typedef-aware Sym.is_string_type alternative. The new predicate does not
resolve typedefs, remove qualifiers, prove a terminating NUL, or detect a
string literal. Those remain different questions with existing owners.

### I10 and I12: show structure and borrowing directly

Current Literal extraction:

```x2c
meta static int var_tag_top(List tag) =>
  (int) Var_tag_top(List_last((List) List_last(tag)));
```

Proposed local extraction and use:

```x2c
meta static Symbol _literal_tag(List tag) {
  match (tag)
    case %(expr ? (literal ? ? ?key)): return key;
  return 0;
}

meta static int var_tag_top(List tag) => (int) Var_tag_top(_literal_tag(tag));
meta static int var_tag_bottom(List tag) =>
  (int) Var_tag_bottom(_literal_tag(tag));
```

Remove the now-unused List_last meta prototype. Preserve the compiled tag
queries, masks, accessors, and leaf ownership. The fallback is not a new
public malformed-input contract.

Current private Match helper parameters and writes:

```x2c
static int MatchPlan._first(
  MatchPlan plan, List input, Var *out_match, List *out_bindings);

*out_match = walk.found;
*out_bindings = walk.bindings;
```

Proposed:

```x2c
static int MatchPlan._first(
  MatchPlan plan, List input, Var &out_match, List &out_bindings);

out_match = walk.found;
out_bindings = walk.bindings;
```

Change the corresponding private calls coherently. The existing public
try_search optional-output checks and return behavior stay. Apply the same
private output convention to _replace_all and _replace. Lisp's _read_form
uses unsigned &cursor and Var &?out; its optional-output guard stays. Published
scanner/parser pointers, callback pointers, arrays, and retained slots stay.

### I11 and I13: relocate ownership or replace the complete bracket

I11 moves definitions rather than adding an abstraction:

| Definition family | Current file | Proposed file | Name/algorithm |
| --- | --- | --- | --- |
| ast_prototype_declarator and _prototype_params | src/type.x | src/ast.x | unchanged |
| addressed/direct/indirect identifier family | src/type.x | src/ast.x | unchanged |
| Type.declaration_ast, parameter_ast, type_from_ast | src/type.x | src/type.x | unchanged |

Consumers keep calling the same exported functions. Regenerated ownership
and documentation change; no aliases or dotted-name wrapper family is added.

For MatchCache construction, replace the complete push/pop bracket:

```x2c
Scope owner = Scope.new_named("Match plan cache");
MatchCache cache;
$scope(&owner) {
  cache = Scope.calloc(1, sizeof(struct MatchCache));
  // Existing cache fields, entries, buckets, and bucket initialization.
}
return cache;
```

For the module reset, replace only its destination bracket:

```x2c
if (!(module in c.meta_group_bound)) {
  c.meta_group_bound[module] = 1;
  $scope(&session_meta_scope)
    ((Func) targets["x2c_module_reset"].pointer()).apply(0, NULL);
}
```

$scope restores the caller's destination on transfer as well as normal exit.
That transfer behavior differs from a skipped manual pop and must be tested.
It does not free the selected Scope or change the owner's lifecycle.

### I02 and the larger I03 experiment: explicit source, computed composition

The callback catalogue experiment would replace two maintained lists with
one row per binding. For example, one List_map row would hold these facts:

| Fact | Concrete value |
| --- | --- |
| Public binding name | List_map |
| Generated private wrapper | _lisp_List_map, derived from the public name |
| Return Type and parameters | List; List values, Var callable |
| Visible source body | values.map(_unary_callback(callable)) |

One projection emits the wrapper from a Unit template. Another supplies
`(_lisp_List_map (as List_map))` to the existing native target owner. The
signature still comes from the emitted function. Lisp_List_filter has an
explicit _predicate_callback body, and Iter_init retains its session-owned
pull callback. Do not encode those differences in an arity/truth flag engine.

This is a prototype, not a selected wholesale catalogue rewrite. Start with
those three representatives and retain direct wrappers if the row/template
composition hides bodies, breaks binding, or costs disproportionate machinery.

The larger Map prototype follows the selector generator's existing shape:

```x2c
// Existing selector example, not new Map implementation:
return %(${middle.startswith("a") ? car(name) : cdr(name)} @rest);
```

Here car and cdr are complete named templates. A Map experiment would select
an explicit boxed-update or native-update Unit template from policy facts.
Each template visibly declares its generated parameters and body. The meta
helper selects and composes templates; the ordinary binder handles names.
It does not inspect and rewrite arbitrary AST variable names. Compare the
complete generated operations before deciding whether that design replaces
the current constant-flag update template.

### Retention decisions are concrete too

I04 keeps Compiler._step's current dispatcher unless the bounded match/defer
comparison shows a benefit while preserving normalization. I09 keeps the five
native Macro_* identifiers and signatures. I14 keeps the eleven explicit
region conversion pairs. None of these gets a cosmetic rewrite.

I15 compares current List-producing quotation forms for empty, single, and
multiple items at the two cold consumers. Keep the existing builders until
the comparison proves Type, order, insertion stage, and identity. The plan
selects that experiment; it does not yet select a replacement spelling.

## What becomes uniform

### Facts and projections

Each fact has one authoritative owner. Multiple consumers may use different
representations suited to compile-time construction, runtime lookup, mutation,
or identity. Generate mechanical consumer lists from that owner when generation
removes a maintained mirror. Do not introduce a ledger solely to replace a
small table if the declarations remain independently maintained.

Keep Map/List/SymbolSet choices contextual. Immutable canonical List rows,
closed Symbol vocabularies, process-lifetime Map indexes, request-owned Maps,
and mutable registries have different contracts. A meta function returning
fixed contents is not the same object as a runtime singleton.

### Syntax and interpretation

Source match names fields when alternatives are recognized locally. Flat
destructuring names a trusted fixed record. Iteration expresses a traversal.
Existing AST helpers own shared structural operations. Short selectors remain
appropriate when they do not repeat a grammatical choice or obscure a field.

Source templates and quotations show generated source where its insertion
stage is correct. Canonical builders remain necessary for inspectable typed
syntax, binding leaves, internal forms, and source forms without a spelling.
Macro patterns can recognize the same source forms the templates construct.
Do not rebind a normalized node solely to make code look uniform.

### Names, borrowing, and lifetime

Ordinary public operations use Type.method. Private context records use value
storage and borrowed reference receivers; Record.step is already allowed.
Native/generated interfaces keep their exact observed names and signatures.
Do not equate matching C symbol output with matching method/reflection facts.

Private synchronous outputs use required or optional references according to
their actual callers. Native callbacks, arrays, retained slots, and published
pointer APIs stay pointers. No parallel wrapper family is added for style.

Lexical destination selection uses $scope where it owns the complete bracket.
Cross-call lifetime, coordinated shutdown, Error-floor initialization, and
conditional entry can retain explicit Scope operations. A macro that restores
a destination does not automatically own or free the destination's storage.

## Design succession and backward adoption

Newness is evidence to inspect, not a ranking rule. Preserve the requirement
and the useful improvement from a newer design, then propagate it to older
consumers that meet the same contract.

| History | Improvement or constraint | Decision here |
| --- | --- | --- |
| d96c4098, September 23 | scalar meta Map replaced Lisp selector machinery; 34 net lines removed in that file | keep Map; eliminate later consumer enumeration instead |
| 8517ce33, September 24 | removed independent native signature column | preserve consolidation; correct remaining stale prose |
| ed863ce0 then cd53416b | structural varops reader predates newer leaf-unbox confinement | combine older readable capture with newer module ownership |
| 608a8ae82, September 30 | introduced shared origin strip/rewrap after field-type loop | adopt strip operation backward in inspection consumers |
| 7ca06d23c0, October 1 | SDK resolves an untyped template expression at expansion | preserve repair while naming the initially matched type |
| 27ee651f4, October 1 | removed unused Array observer facts and shared Map scaffold | propagate unused-slot cleanup to Map; preserve callback choices |
| self-expression decision 4 | Gary retained Map core callbacks | no callback-eliminating family configuration replacement |
| active quotation audit | staged builders and quotations have different contracts | compose at correct stage; do not globally replace AST Lists |
| 9636ee2a/0bbb29d6 then 4a1921af/d9440161 | selector templates and meta name generation now replace repeated bodies and enumeration | use as the current declaration-projection and template-selection example |
| 182d0175/6bf6cfca | compiler field-copy/set statements now share explicit field lists | reuse for the same assignment role; preserve per-field evaluation and fresh values |
| efc7f318 | direct SymbolSet literal replaces the nonreturning cause Lisp projection | prefer the direct literal for this closed membership role |
| ef8bfbf1 | Pool intern storage reuses Map core over a single-Var record | preserve specialization and include it in any core/scaffold change |

Historical patch measurements stay attributed to their workloads and files.
They are not measurements of this proposed plan. An old failed prototype
rejects that implementation; a new capability may justify a fresh bounded
comparison. Neither old success nor old rejection substitutes for current
source and consumer evidence.

## Remediation batches and dependencies

These are coherent implementation boundaries, not required commit counts or
new gates. The same implementation session can combine compatible work.

| Batch | Concrete result | Depends on / conflict boundary | Acceptance |
| --- | --- | --- | --- |
| A. Fixed facts and unused forwarding | I01 declaration projection/stale prose; I03 unused internal slots; I10 Literal capture | Preserve original custom-family surface; scalar projection must expand before lookup references | fourteen access declarations and exact native operations; untouched custom-family fixtures; nine unbox accessors |
| B. Structural input consumption | I05 SDK; I06 initializer; I07 origin inspection; I08 char shape owner | Respect active normalization, qualifier, and source-origin repairs | unchanged accepted forms, IDs, conversion effects, warnings, origins, and char truth table |
| C. Ownership and borrowing | I11 AST relocation; I12 four private reference changes; I13 two lexical brackets | I11 follows settled names; I12 touches Lisp, coordinate with A/I02; I13 preserve reset ordering | unchanged exported names/reflected public types; destination restored on normal and transfer exits |
| D. Callback composition comparison | I02 representative catalogue and optional full adoption | after A scalar declarations; never duplicate native signature owner | List.map, Lisp_List_filter, Iter_init prove identity, truth, session, and storage; account for all templates and registrations |
| E. Broader composition comparisons | I04 match/defer dispatcher; I03 meta selection of named update/postfix templates | optional, independent of small unused-slot cleanup; Map core/scaffold changes also cover PoolTable | preserved custom binding and normalization; no extra semantic walks; total machinery/cost compared |
| Existing quotation work | I15 cold library List construction | reconcile with quotation-adoption audit; compare current forms before proposing syntax work | inspectable/canonical result contract and caller stage preserved for empty, single, and multiple items |

I09 and I14 are explicit retention decisions, not forgotten backlog. No public
API migration, new language syntax, generic container framework, reflective
effect registry, universal copy algorithm, or global naming campaign is
selected. Existing recorded work remains with its owner.

For each optional comparison, the implementation default is deterministic:
start with the stated representative cases; adopt only when all listed
contracts pass and the complete composition removes a mirrored fact or makes
the policy substantially more direct without disproportionate new machinery.
If it does not, retain the current source and record the exact failed shape,
output, or cost. Do not compensate with another binder or policy interpreter.
Do not expand to every family before the representative evidence exists.

## Verification, costs, and completion

The detailed plans select existing suites and fixtures for the changed role.
Reuse the compiler fixture runner in check mode and normal runtime harness.
Do not rewrite expectations to make a supposed behavior-preserving change
pass. Generated declaration movement and private-name/order differences must
be explicitly explained; results, warning contracts, and public names must
remain consistent with the plan.

Focused validation covers scalar widths/alignment/load/store and REPL access;
custom Map/Array normal/live-symbol generation; boxed/native absence and
update atomicity; callback truth/session/destination ownership; nested and
native-dependent initializers; SDK bindings/template types; origin handling;
char pointer/array qualifiers; Match outputs; lexical Scope restoration; and
cleanup/prototype designation behavior. If the Map core/scaffold changes,
include Pool canonical identity, insertion status, locking, promotion, and
ownership behavior. A forwarding-only operations cleanup does not change
that core and need not expand into a Pool rewrite.

Use paired cost comparisons when a proposed change affects a hot path or
raises a concrete runtime, generated-code, or build-cost question. Cold
spelling changes need no performance checkpoint. Use the same workload and
compiler with absolute source/generated
counts and measured times or instruction counts. Count new catalogues,
templates, helpers, imports, compatibility code, and deleted mirrors together.
Relocation is not a code reduction. Fewer arguments are not a throughput gain.
Optimized-away constant branches are not established runtime overhead.

On authorized implementation, refresh the actual dev baseline and inspect
conflicts with current plans. Build the fresh compiler through the prescribed
ordinary path. Review and fix the completed authored diff before the existing
final-tree publication gate. There is no new recurring validation, planning,
commit, or benchmark requirement. This task saves plans locally; it does not
commit, submit a PR, or publish source.

An item is complete only when its selected rewrite has the specified evidence,
or its retention/prototype rejection has an explicit reason at the current
revision. Record actual additions/deletions after a patch exists. Close plan
items against those delivered changes rather than an overall percentage.

## Binder annotation decision and prerequisite repairs

`?(Type name)` is native type syntax inside a pattern. The parser calls
`parse_type_name`, so typedef names become String-backed Type Lists.
`?(Long value)` uses `%("Long")`; it does not read `%(Long)` as a literal
Atom. Long identifiers preserve their complete spelling and case.

`Type` is a typedef of `List`. A Type capture therefore tests the List Var
tag before extracting the value. It does not validate the captured List's
contents as a type. Compiler-generated forms establish their own structure.
Compile-time Lisp can construct canonical forms without origin authentication.

I05 and I06 use untyped named captures under the original structural
patterns. This preserves accepted shapes without introducing List-tag filters.
The concrete walkthrough now shows these untyped captures. The book explains
typed capture syntax separately from this acceptance-preserving cleanup.

The investigation reproduced three distinct defects at c5c84a5d:

| Defect | Baseline observation | Repair and regression |
| --- | --- | --- |
| Alias `typedef String Long` selects `Var_long` | A capture and ordinary Var assignment emit an incompatible native long return | Compare declared converter return types after alias normalization; test `Long`, `long`, case-distinct long names, and compatible return aliases |
| Builtin typedef lookup truncates identifiers | Undeclared `uint64_trick` is accepted by `is` as a builtin numeric type | Match the complete String in the existing Type List; test known aliases and rejected prefix collisions |
| Type quotation accepts long Atom names | `%(ExtremelyLongCamelCaseCaptureType)` passes where `%(String)` rejects | Extend the existing type-name check to the long Atom representation; preserve the same String diagnostic |

The third repair enforces the existing documented representation at the
existing quotation boundary. It adds neither a recursive Type validator nor
origin tracking. This preserves user-space String type names and ordinary
macro construction of canonical Lists.

The book now distinguishes native capture annotations, literal Atoms, and
String-backed type Lists. Passing alias/capture checks establish the binder
syntax conclusion independently of the three adjacent repairs.

## Private implementation record

All selected source rewrites are retained locally on
`codex/idiom-synthesis-refresh`, now based on fd88fae4. Gary authorized commits
and pushes to this branch alone. No PR or integration into dev is authorized.
I04, I09, and I14 retain their established
contracts; they require no rewrite. I02 and the larger I03 candidate retain
the current implementation after the bounded comparisons below.

| Item | Current location and physical file size | Concrete result |
| --- | --- | --- |
| I01 | [lib/native-scalar-types.xmacro](../lib/native-scalar-types.xmacro#L80), 106 lines | Scalar declarations derive from the existing Map; all 14 records are preserved. |
| I03 | [lib/map-generics.xmacro](../lib/map-generics.xmacro#L690), 955 lines | Unused internal parameters removed; outer family contracts preserved. |
| I05 | [src/meta-sdk.x](../src/meta-sdk.x#L60), 658 lines | Named captures retain original wildcard patterns and SDK checks. |
| I06 | [src/initializers.x](../src/initializers.x#L33), 1,100 lines | Both callers pass captured composite items; transactions and fresh containers remain. |
| I07 | [src/type.x](../src/type.x#L144), 894 lines | Inspection uses Ast.without_origin; reconstruction keeps original origins. |
| I08 | [src/type.x](../src/type.x#L472), 894 lines | One compiled predicate; transform alone explicitly canonicalizes first. |
| I10 | [lib/var-unbox.xmacro](../lib/var-unbox.xmacro#L16), 35 lines | Literal field captured structurally; compiled tag queries remain. |
| I11 | [src/ast.x](../src/ast.x#L76), 393 lines | Four exported structural functions and one private helper relocate unchanged. |
| I12 | [lib/match.x](../lib/match.x#L688), 1,402 lines | Three private Match outputs and Lisp reader cursor use references. |
| I13 | [lib/match-cache.x](../lib/match-cache.x#L544), 581 lines | Two complete allocation destination brackets use $scope. |
| I15 | [lib/var-tags.xmacro](../lib/var-tags.xmacro#L267), 395 lines | Two quotation expressions replace repeated canonical AST field spellings. |
| Binder repair | [src/expressions.x](../src/expressions.x#L3680), 3,925 lines | Normalized return types prevent Long selecting Var_long. |
| Builtin repair | [src/symbols.x](../src/symbols.x#L1074), 1,421 lines | One private String-keyed Map resolves all 29 exact aliases. |
| Quotation repair | [lib/meta.x](../lib/meta.x#L362), 407 lines | The existing String-name requirement also rejects long Atoms. |

Across 18 hand-authored lib/src files, this patch currently adds
232 lines and deletes 239 lines: 7 net lines removed.
These counts exclude plans, tests, book prose, and derived artifacts. Moving
structural AST functions is ownership clarification, not source deletion.
The batch therefore offers modest size reduction. Its main benefit is fewer
maintained definitions and three reproduced correctness repairs.

### What the competing proposals demonstrated

The callback catalogue's anonymous Unit row cannot run because local macros
cannot have Unit results. A different Function-forwarding candidate does run.
It derives aliases from wrapper names and passes all 84 Lisp tests, plus
explicit truth, destination identity, retained iterator, and session probes.
Full adoption would save 12 authored lines but adds a mutable compile-time
Array registry. That registry introduces inherited-state, sharing, and
lifetime obligations. Retain direct wrappers and aliases for this batch.
This rejects the measured candidate, not future catalogue designs.

The Map Unit-selection candidate also runs. Native custom-family output is
`2 25 10 1 55 2 55 2`; the boxed probe is `1 10 15 15 16 1`. Its generator
grows from 955 to 1,005 lines and duplicates shared control flow. Smaller
generated C does not establish a runtime gain because constant branches may
already disappear under C optimization. Retain the common template and
adopt only the independently verified unused-argument removal.

The cold tag List builder now uses ordinary quoted null and cons expressions.
Complete table values and canonical identities agree. At `cc -O2` on macOS
arm64, the compared tag projection uses 4,104 versus 4,096 text bytes, with
identical call counts. Generated C grows because quotation adds temporary
scaffolding; the optimized comparison prevents misclassifying that scaffolding
as runtime cost. Allocating Lists before the Map changes construction order;
allocation-failure order was not proven identical. The cold projection has no
explicit public allocation-order contract and uses immutable constants.

The scalar List quotation alternative needs eight authored lines, including a
Lisp bridge, versus the current four. Keep the existing scalar helper. The
counted List constructor introduces temporary Array work; keep direct cons
construction. These outcomes establish feasible compositions without assuming
that every syntactical unification earns adoption.

The builtin alias repair initially used exact String patterns. A private Map
preserves all 29 aliases and four absent/case-sensitive names with one lookup.
For one million warm lookups over an equal known/unknown eight-key mix, the
exact-pattern candidate takes 0.277-0.293 seconds; the Map takes
0.0137-0.0144 seconds. This compares two correct lookup implementations,
not whole compiler performance or the former unsafe Symbol switch. The Map
adds startup storage, with no allocation per lookup. LLP64 was not executed;
both existing host-width branches remain in source.

### Verification and remaining delivery work

The final Map and quotation batch built through strict stages 1 and 2 and
produced identical 220 C/H files. Bootstrap was generated through its ordinary
target from the working compiler; `make build-safe` then rebuilt the fresh seed.
No bootstrap file was hand-edited. All 1,061 compiler fixtures passed, covering
2,389 artifacts. The full runtime suite passed 940 tests and 24,988 assertions.

Final artifact review found that exporting the shared character predicate
inline duplicated literal caches in every including compiler header. The
predicate now has one compiled definition. Its source behavior is unchanged;
the final rebuild, bootstrap regeneration, and strict stage comparison passed.
All 220 generated C/H files agree between stages 1 and 2. After this correction,
the full runtime suite again passed 940 tests and 24,988 assertions, and all
nine focused compiler fixtures passed. The regenerated bootstrap compiler
also translated the five affected Type, symbol, ledger, and Lisp units.

Binder regression fixtures demonstrate baseline failure and repaired behavior.
Generated scalar declarations contain the same 14 names, tags, size types,
and alignment types as the original calls. An inert transfer probe prints
`1 1`, proving Scope destination restoration on a caught transfer and after
MatchCache construction. The larger normalizer dispatch prototype was not
attempted: its default retention decision remains, and no throughput claim
is made for it.

The documentation audit passes after saved plan links use portable repository
paths and `#L` anchors. No checker rule was changed. Generated API ownership
and source locations reflect the moved AST functions and shared Type operation.

Workspace experiment evidence is saved in `.context/idiom-builtin-map.md`,
`.context/idiom-callback-prototype.md`, and `.context/idiom-i03-i15.md`.
The conclusions and material limits are recorded here so the durable plan
does not depend on temporary probe directories.

Branch-only delivery now requires the existing final-tree publication gate,
review of its derived deltas, and a commit and push to
`refs/heads/codex/idiom-synthesis-refresh`. Its execution log is retained in
`debug/idiom-dev-refresh-gate.log`. This delivery does not create a PR or
advance dev or main. Any later integration must refresh its intended base
and validate the resulting tree. No recurring process or gate was added.

## Plan review

The parser and resolver establish canonical syntax, binding operations establish
IDs and typed leaves, native signature owners establish callable interfaces,
runtime producers establish storage/effects, and normalization establishes
sequence/cleanup/origin order. This synthesis preserves those boundaries and
does not add consumer checks for facts already established there.

The definite edits delete maintained enumerations, unused internal forwarding,
repeated field extraction, inspection loops, duplicate character patterns,
and misplaced structural ownership. They reuse current Map projection,
Match, Type, AST, reference, and Scope operations. Callback and policy
prototypes must account for every added helper and representation before
adoption; generation alone does not justify keeping them.

The result uses ordinary x2c concepts in combination. Real stage, identity,
native ABI, arithmetic, absence, lifetime, and export distinctions remain
explicit. No second grammar, binder, registry, signature model, or general
framework is required by the selected work.

The original simplification proposal adds no validator or dedicated
diagnostic. The binder investigation separately reproduced public-boundary
defects; their repairs extend existing checks and add focused regressions. An
inert focused probe can demonstrate a changed transfer or binding boundary
without adding a recurring process or new runtime failure policy.
