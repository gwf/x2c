# First independent consolidation: macro capture roles

Read-only scope at 1b23aaa7e103461c3b219b9e10546aeb35384b60. No production
implementation, branch creation, bootstrap refresh, commit or push. The
requested future first production change can be independent of open templates,
stage/effect ABI and compiler lowering migrations.

## Verdict and smallest boundary

Consolidate the **capture projection schema**, not recognition semantics or
all macro application. `_capture_pattern` and `_capture_row` are opposite
projections of existing capture rows. They intentionally do different work:
one builds an ordinary Match pattern, the other preserves captured syntax and
source. A shared static role table can eliminate their duplicated projection
names, cardinality and row-layout policy without changing their outputs.

Keep `_capture_pattern` and `_capture_row` as thin direction-specific entry
points; use one private role/schema owner for projection keys and common row
assembly. `_forwarded_capture` and `_forwarded_prefix_list` consume the same
schema. Do not replace these with a new matching engine, stage carrier or
recursive semantic validator. Ordinary List.replace, Match, binding, source
capture, member projection and expansion/freshening stay unchanged.

A table that only renames four strings would be too small to accomplish the
intended consolidation. A generic callback-driven projection framework would
be too large. The proportionate owner is a compact private static table whose
rows specify field/projection name, scalar-vs-sequence key policy and storage
location, with ordinary explicit code for the three special existing cases
(Function subfields, Unit requirements and Name member spelling).

## Existing call graph and invariants

References are current source line numbers, not the older survey's offsets.

| Entry | Consumers | Fact that must survive |
| --- | --- | --- |
| `_capture_pattern` src/macros.x:2832-2879 | `_invocation_pattern`: formal arguments, decorator target, Lisp-visible fresh Name captures (2880-2906) | Existing definition Match pattern and every projection binder spelling/order must remain the same. Only template-used internal projections become named captures; wildcard positions remain ordinary Match wildcards. |
| `_capture_row` 2965-3009 | SDK/deferred template call 3027; ordinary invocation arguments 3882; Lisp-visible fresh binding rows 4070; expression decorator 4145; statement/unit decorator targets 4345 | Exact source carrier and canonical value/expression/splice projections are retained. No binding/type/source policy change. |
| `_forwarded_capture` 2921-2960 | singular and per-element sequence paths inside `_capture_row` | Forwarding reconstructs original capture projections instead of granting source text to freshly constructed syntax. Unit construction requirements travel with forwarded value. |
| `_forwarded_prefix_list` 2911-2917 | `_forwarded_capture` recognizes private projection key prefixes | Keys come from `_replacement_binder` (2736-2739); author '?' sentinel gives empty author label. Do not hardcode a second prefix grammar. |
| `_parse_hole` 3143-3192 | parser slots through try_parse_macro_slot | Selects source/value/expression/splice by grammatical role; Type is a splice even though it is one singular logical value. Inference/mismatch diagnostics remain its owner. |
| `_member_bindings` 3921-3946 and try_parse_macro_member 3948-3958 | invocation expansion direct replacements | Member projection is source spelling, including source-spelling binding facts. It is not ordinary program binding identity. |
| expansion fresh rows 4062-4086 | existing expand_macro_invocation_node | Fresh allocation order, direct binding replacements and existing supplied Name identity remain unchanged. |

Existing role schema:

| Role | Scalar key / sequence key | Actual row storage and direction policy |
| --- | --- | --- |
| author | the hole's own ?name/*name | Pattern binds it against source field, preserving SDK/Lisp source capture behavior. It is not another serialized row field. |
| source | ?__macro_source_name / *__macro_source_name | `(source captured...)`; source wrappers preserved and forwarding retains registered capture. |
| value | ?__macro_value_name / *__macro_value_name | `(value unwrapped...)`; `_source_unwrap` removes src wrappers, not binding records. |
| expression | ?__macro_expression_name / *__macro_expression_name | Scalar `(expression expression)`; String/Binding Name gets `(expr () (ident name))`. For sequence, the pattern reads the **same value field**, not a serialized expression row. |
| splice | *__macro_splice_name for both scalar and sequence | Scalar `(splice @List(value))`; non-List scalar gives empty splice. Sequence pattern reads the **same value field** through a list binder. |
| return / declarator | scalar ?__macro_return_name / ?__macro_declarator_name | Singular Function pattern constrains nested value `(function return declarator ?)`. These are virtual subfield projections, not extra capture-row fields. |
| construction | *__macro_construction_name | Unit requirements are trailing row material. Pattern appends them only under its current precise used-role condition (author/source/value/splice/construction, not arbitrary any-role activation). |
| member | ?__macro_member_name | Name singular only, added as direct replacement by `_member_bindings`, not serialized in `_capture_row`. Source-spelling fact may differ from emitted fresh spelling. |

A sequence actual capture row has source/value fields and trailing construction
requirements. Its definition pattern uses `!and` to alias value, expression and
splice projections from that one value field (2858-2865). Do not “simplify” by
adding scalar-shaped expression/splice rows to every sequence: that changes the
canonical descriptor/invocation contract and forwarding behavior.

Scalar source/value/expression/splice row order is stable. Singular means one
item and not a sequence; `_capture_row` has existing empty/multiple nonsequence
fallback behavior. This consolidation must retain it, not add another arity
checker or silently broaden forwarding to Function/Type/other kinds.

## Suggested internal layout and deletions

Use a file-private static schema, with no runtime public API:

* Standard rows: source, value, expression, splice; storage is source field,
  value field, scalar expression field/sequence alias, scalar splice field/
  sequence alias respectively.
* Virtual rows: Function return/declarator, Unit construction suffix, Name
  member replacement. Predicates use the existing kind/sequence facts.
* One `_capture_projection_key(author, role, sequence)` delegates to existing
  `_replacement_binder`. Splice/construction always use list keys; other rows
  use the schema cardinality. Keep current key strings byte-identical.
* One direction-neutral row assembler handles scalar versus sequence row order.
  Pattern direction supplies used binder/wildcard values; capture direction
  supplies already-produced original/unwrapped/expression values. The existing
  Function and Unit structure remains a short explicit branch in the owner.

Delete repeated per-role key setup in `_capture_pattern`, `_forwarded_capture`
and prefix enumeration; consolidate the row shape assembly shared by pattern
and capture direction. Remove the hardcoded four-name list in
_forwarded_prefix_list. Do not delete `_source_unwrap`, `_capture_source`,
`_projection`, `_template_binders`, `_lisp_bindings`, `_member_bindings`,
`_introduced_binding` or `_invocation_pattern`: each still owns real independent
behavior. Move Name member key naming to the schema only if it actually removes
duplicated policy; don't migrate unrelated parser slot dispatch in this first
change.

The schema can be implemented with ordinary static structs/enum/loops already
accepted by the checked-in compiler. Avoid per-invocation heap-allocated role
Lists or a dictionary of callbacks. Static role descriptions are prepared once;
projection values remain per capture. There is no justified fixed line-count
claim before a reviewed implementation shows real deletion.

## Compatibility and focused validation

Intent is unchanged parser grammar, captured rows, stored definition patterns,
source SDK behavior, diagnostics, generated bindings and generated program C.
It affects legacy macros regardless of new first-class Macro prototypes, so
validate existing cases rather than only the spike's arithmetic examples.

Relevant current fixtures already exist:

* macro-argument-kinds: Expr/Type/Decl/Function/Name/Literal/Param/Block/Field/
  Unit and empty Unit sequence.
* macro-sequences, macro-sequence-nonfinal: sequence shape and current rejection.
* macro-source-text, macro-source-parity, macro-source-text-decorator: exact
  original/forwarded text and source-wrapper contract.
* macro-source-text-derived / constructed / name / outside: existing source
  access rejection behavior; no new source authority added by table lookup.
* macro-decorators and macro-target-forward: Function subfields and unchanged
  target publication.
* macro-decorator-public-two-level-drop / variadic-drop / lisp-siblings and
  related negatives: Unit construction obligations survive forwarding.
* macro-member-name-hole / macro-postfix-members / macro-template-lexical-shadow /
  macro-local-reference-shadow: member spelling and lexical identities.
* macro-construction-regressions: inserted Names/types and existing construction.
* meta-template-calls: SDK/deferred/native helper crossing of ordinary rows.

Run focused fixtures using the existing fixture harness; never rewrite
expectations to disguise an accidental contract change. Add a new focused case
only if the refactor reveals an unrepresented role combination whose failure
would be consequential. For structural parity, compare stored pattern/capture
outputs old/new on existing inputs; comparison should be exact canonical List
structure and existing emitted C/diagnostic sidecars, not alpha normalization.
This is an implementation-specific validation proposal, not a new recurring
process target.

This refactor needs **no language-transition bootstrap stage**: no new syntax,
new result envelope or new runtime type enters src/. Normal later-authorized
publication handles generated bootstrap and self-host comparison through existing
owner targets. The separate new Macro/open/slot/effect contract does need its
intermediate compiler before source consumers migrate; that is not a blocker
for this first behavior-preserving consolidation.

## Review of the frozen requirements

Freeze four forms (`Macro m=$name`, `m(args)`, `case m(...)`, anonymous macro),
explicit open free-global policy, ordinary meta calls in all legal template
slots (including existing sequence insertion), logical slot result semantics,
source/bound/lowered marks and the producer inventory. Producer implementations
should be added only as the first lowering requires them, not all at once as an
API platform. Clients never read descriptors/stage/effect envelopes.

This frozen list does **not** need to block capture-schema consolidation.
Its first production scope only shares present role policy and preserves the
old wire forms. It does not deliver open globals, stage marks, effects,
automatic mixed Name constraints, exact source interior spans or syntax-rule
recognition. Those later owners can consume the shared table without changing
this refactor's public behavior. Fixing logical Type ? capture or recognizing
Name binding/member correlations must remain separate authored semantic changes.

Remaining frozen-contract decisions still requiring evidence: grouped sequence
call ABI; effect-reference relocation across Name/Type/Expr/member roles;
open value/type/tag lookup including native declaration timing; scalar/data
versus code returned by slot calls; lowered-slot conversion boundary; rollback
of all mutated compiler stores. Source/bound/lowered describe producer promises,
not a provenance validator. Recognition must preserve binder relations even
where IDs and spelling are derived. A table that stores role facts is reusable
without pretending these remaining semantics already work.
