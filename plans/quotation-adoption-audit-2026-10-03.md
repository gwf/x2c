> Status: reference
> Audited origin/dev 32c6e1293e72d9d99398ec005dbeaa3d5ed231bc.
> The accompanying change adopts cold source generators and examples.
> Language refinements and compiler hot paths remain proposals.

# Quotation adoption audit, October 3

## Scope and counting

The survey screened authored src/, lib/, etc/, commands/, packages/,
examples/, and book code for List construction, syntax builders, source
content helpers, named templates, quotation use, and compile-time Lisp.
The classified inventory below counts named construction operations or
coherent families. It is not an exhaustive count of every raw List literal.
Patterns, type data, diagnostic data, transport records, and toy languages
are not quotation opportunities. The two source-file rows instead count
individual `%(` openings outside comments; their unit is explicit.

| Area and counting unit | Convertible now | Needs language refinement | Retained |
| --- | ---: | ---: | ---: |
| lib generators, operations | 4 | 2 | 11 public builder operations |
| builtins, operations | 6 | 0 | 4 conditional/already quoted operations |
| grammar.xmacro, List literal openings | 0 | 0 | 15 |
| meta-sdk.x, List literal openings | 0 | 0 | 78 |
| REPL, construction operations | 0 | 0 | 2 |
| packages, candidate operations/families | 1 | 1 | 17 |
| executable examples, production family | 1 | 0 | toy List interpreters |
| book, code production examples | 3 | 0 | canonical-builder demonstrations |
| etc, builder operations/internal forms | 0 | 0 | 4 builders and 3 internal forms |

The package row counts yyjson's `_json_call` as convertible. It retains
17 screened autodiff operations pending connected caller-stage and cost
review: `ad_zero`, `ad_one`, `ad_neg`, `ad_id`, `ad_assign`,
`ad_call`, `ad_select`, `ad_less`, `ad_less_eq`, `ad_fwd_decl`, `ad_fwd_body`,
`ad_fwd_item`, `ad_stmnt`, `ad_accum`, `ad_set`, `ad_cast`, and `ad_code_is`.
The parameter gap is `ad_fwd_params`. Dynamic-operator `ad_raw` and
textual numeric `ad_lit`/`ad_int` are additional retained producers, outside
that curated 17-operation inventory. Other reverse-mode constructors were
screened, but not fully classified or experimentally rewritten.

An initial expression-level shortlist counted 13 package candidates. Caller
inspection superseded that count before package implementation. Canonical
inspection is confirmed for core expression utilities such as ad_zero,
ad_one, ad_id, and ad_stmnt. Other operations, such as ad_code_is, have
source-expressible output but remain unprobed candidates; the audit does
not establish that every retained operation must stay raw permanently.

Generated src/linked-meta.x contains 92 raw List openings. It mirrors
lib/meta.x and imported macros; it is not a second authored opportunity.

## Ranked ten

| Rank | Site on audited base | Before | After sketch | Risk/cost |
| --- | --- | --- | --- | --- |
| 1 | lib/var-tags.xmacro `_tag_id_checks` | equality + c-assert + message AST | `$!Unit{ _Static_assert($id == $index, "..."); }` | low; cold ledger projection |
| 2 | lib/var-tags.xmacro `_tag_bits_expr` | nested sizeof declaration/operator AST | `Type type = bits; $!( sizeof($type) * CHAR_BIT )` | low; verify width and spelling |
| 3 | lib/varops.xmacro `_update_box` | index/cast/call builders | quoted index, optional cast, then `$!( $boxer($value) )` | low; keep existing identifier child |
| 4 | lib/varops.xmacro `_update_decode` | call and optional cast builders | `$!( $decoder($value) )`, optionally `$!( ($back)$decoded )` | low; Type cast hole |
| 5 | src/builtins.x `_assign` | statement wrapping operator builder | `$!{ $target = $value; }` | caller-stage and cost review |
| 6 | src/builtins.x `_declare` | bind/modifier/initializer Lists | initialized/uninitialized declaration quotations | shared-name and Type-hole review |
| 7 | src/builtins.x Foreach.with_cursor | block List around assignments/body | `$!{ { $assignments... $body } }` | expansion-cost measurement |
| 8 | src/builtins.x Foreach.with_iter | same block assembly | same quotation | expansion-cost measurement |
| 9 | packages/yyjson/src/json-api.xmacro | nested identifier/call builders | `$!( $callee($argument) )` | low; package-specific check |
| 10 | examples/magic/meta-functions.x field_reads | dynamic member builder | `$!( $receiver.$member )` | low; name-hole check |

Two more builtin candidates are `_call` and `_binding_call`; both can use
a callee expression local and argument sequence in one quote. Retained
conditional families are `_iter_call` (explicit Iter root type),
`_fields_hash` (one name shared by separately built statements),
`_binding_target` (composition/phase review), and `_hash` (already quoted).

## Findings beyond the shortlist

- src/grammar.xmacro's 15 List literal sites comprise three exact
  constructors, ten structural patterns, and two pattern-binding Lists.
  The content helpers deliberately preserve arbitrary operator tokens,
  type shells, omitted fields, and parser-introduced data.
- src/meta-sdk.x has eight AST construction sites among 78 List literals.
  Six preserve typed binding leaves; two reconstruct a declaration for an
  immediate type query. Quotations would alter stage or add binding work.
- The 11 lib/meta.x public expression/statement/declaration/parameter
  builders return inspectable canonical syntax. Changing them to pending
  quotations changes their contracts. Adopt quotations at callers instead.
- etc/meta-helper.x duplicates four such builders. Preserve their output.
  etc/builtin-macros.xmacro constructs falias, tadapt, and managed-init;
  these are internal operations, not C fragments.
- etc/compiler-sdk.xlisp delegates to canonical builders. Other .xlisp
  files build Lisp forms or runtime data, not replacement C syntax.
- commands/repl `_thunk` owns its sentinel binding identity; `_result_body`
  constructs a typed return. Graph/lint and C* tools inspect syntax or
  build analysis records. No command change is recommended.
- examples/power/match.x and independent Lisp interpreters manipulate
  their own data languages. Their AST-looking Lists should stay raw.
- Named source macro screening found 30 macros with one additional textual
  reference. This is a discovery count, not proof of single semantic use.
  Descriptor tables, defer callbacks, aggregate initialization, and module
  entry functions are follow-up families. Inlining them adds no capability
  and needs stage, identity, and cost evidence.
- docs/src/guide/meta-functions.md incorrectly said nested hand-built call
  arguments leave quotations unexpanded. src/expressions.x resolves their
  carriers, and macro-quotation.x exercises that behavior.

## Language refinements, proposals only

1. Sequence holes in List and composite literal quotations. Two concrete
   producer operations are `_tag_list` and `_tag_composite` in
   lib/var-tags.xmacro. `$!( [$items...] )` and `$!( { $items... } )` both
   fail with sequence insertion illegal in an expression slot. This proves
   those spellings fail; it does not rule out another representation.
   Reuse literal element/comma parsers and produce the same canonical AST.
   Keep one-element composite versus statement-expression rules explicit.
2. Standalone existing syntax categories, especially Param, Type, and Decl.
   macro_categories already has their hole categories but no result kind.
   Three parameter-producing operations are x2c_param_make in lib/meta.x,
   its etc/meta-helper.x counterpart, and ad_fwd_params in autodiff.
   `$!Param{ $type $name }` could serve new source-facing callers; it must
   not silently change immediate canonical builder contracts. Specify one
   node versus sequence and semantic Type versus declaration AST first.
3. Category-specific structural rebuild for Unit/Field/declarator syntax.
   Four concrete families are meta-group helper prototypes and entry
   functions, callable capture fields, and cleanup capture fields. Reuse
   `_rebuild` if a measured connected adoption justifies it. Keep supplied
   lowered children and binding identities; do not bind the result again.

There are no operator holes. Dynamic operator/type/identity records are
not grounds for replacing Lists with a second AST representation. Source
quotations should stay another producer of the existing canonical grammar.

## Implementation and validation decisions

Adopt four library generator operations, yyjson's call generator, one
executable field-projection family, and three corresponding book examples.
Correct the nested-expansion prose. Add no compiler semantic operation,
public syntax, validator, diagnostic, fixture, or recurring gate.

These library generators run when producing ledger tables or native
family definitions, not for each resolved compiler expression or call.
No new bind_syntax/rebuild_expression invocation is added.
The first library build met the old shipped-meta hashes. A temporary
compiler was built with the existing runtime archive and refreshed
linked-meta source; the next build and bootstrap refresh used that compiler.
The ordinary bootstrap refresh and safe rebuild then repeat without an
override to verify the supported seed path. Compiler
hot-path candidates are intentionally unimplemented; they need the user's
converged instruction-count A/B before any such rewrite.

Validate with before/after self-translation of all src/*.x in this checkout,
focused example/package checks, every compiler fixture, and make verify.
Review all generated-C differences. If bootstrap is refreshed, rebuild
it safely and repeat source translation and compiler fixtures. Do not run
the publication gate. Submit a ready PR to dev through integrate-dev.py.

## Plan review

The existing binder owns source semantics and expands quotation carriers
nested in expression syntax. The casts retain declared Type holes; binding
leaves retain their existing construction. Supplied member/callee names
remain external holes rather than private declarations. The change deletes
manual source construction and reuses anonymous macros. No helper system,
representation, traversal, cache, validator, diagnostic, or negative fixture
is added. Canonical builders, shared names, and lowered nodes stay intact.

## Generated-C review

Before/after self-translation at the same source path changes only
linked-meta.c; 44 other C files and all 45 headers are byte-identical.
The four changed bodies now construct pending quotation carriers instead
of direct builder ASTs. Their inline Macro definition/pattern/type data
adds cached List, String, and Var constants; removed literal-builder data
disappears, and later cache identifiers are renumbered. The shipped meta
hashes and function-call metadata update for those four bodies. Remaining
function changes are cache-name references and macro temporary numbering.
No other compiler operation changes. Stage output uses ../../src paths,
while the audit uses src paths; quotation origin cache rows therefore differ
between those two invocations. Compare before and after with matching paths.

The generated linked-meta.c workload grows from 197,890 to 227,339 bytes
in the matching-path comparison. Static text contains 1,617 versus 2,125
cons calls; these are source counts, not measured retired instructions or
runtime allocations. Anonymous template definitions explain that increase.
No throughput improvement is claimed. Separate translation of lib/var.x
and lib/varops.x produces byte-identical C and headers before and after.

## Validation outcome

- Ordinary bootstrap refresh and safe rebuild passed after the intermediate
  transition. Every bootstrap C/H file matches the rebuilt stage 0 output.
- Matching-path self-translation: linked-meta.c alone changes among 45 C
  files; all 45 headers match. Both focused library C/H pairs match.
- Compiler fixtures passed twice: 999 fixtures and 2,274 artifacts, including
  the run inside make verify after the final seed rebuild.
- make verify passed: 939 unit tests, 24,918 assertions, all compiler
  fixtures, and the CLI, scope, error, varops, and other required probes.
- The executable meta example matches its checked-in stdout. yyjson tests
  passed: 27 tests and 149 assertions, using its existing dependency cache.
- make doc-examples reports only the unrelated site imports sample needing
  packages/pcre2/builds/libpcre2.a. No edited sample fails.
- git diff --check passed. No publication gate or hot-path instruction A/B
  was run; compiler hot-path rewrites were not attempted.

## Follow-up: sequence splices in literals

Refinement 1 is implemented. A quotation's `$name...` now splices into
`%[...]` Array literals (inside `%[...]` the splice scans as the atom
`...`), and Map entries splice as `%{${$rows...}}`, as in templates. A
sequence hole also splices into braced initializers in templates and
quotations: `(T){ $first, $rest... }`, `$!( { $items... } )`, and
`T v = { $items... };`. A Lisp slot or meta call inside braces stays one
element.

Converted with it: the lib/var-tags.xmacro tag, numeric, and decode tables
(deleting `_tag_composite`; the generated tables are unchanged apart from
`0x8000` keeping its spelling), the protocol descriptor table (deleting
`$methods_table` and `$methods_value`), `CaptureBuild._storage`, builtins
`_positional_new`, and the three `x2c_expr_composite(reads)` teaching
copies. Generated C outside the edited compiler files is unchanged.

Kept raw: hand-built `char *` literal producers in stage.x, expressions.x,
and literals.x (they are the literal constructors), transform.x's raw
string segments (per segment), meta-group.x's lowered module stamp, and
stage.x's Array and Map forms (no shorter), and the descriptor
registration calls. Bound as quotations, those calls add the runtime
prototypes to every unit with protocol registrations, and a string literal
at their `String` parameter was emitted as a bare C literal, which has no
String header; that emission is recorded for investigation.
