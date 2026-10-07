# Macro sequence splicing with @

> Status: active
> Planning only, revised 2026-10-07. No compiler implementation has started.
> Branch: `codex/macro-at-splicing`.
> Baseline: `origin/dev` at `ae34288c8a4de03168e4055d885b796cbc35da27`.
> The branch fast-forwarded to this snapshot. The October 4 plan was
> recovered from local snapshot `332d0bc3` and revised against current code.
> Delivery: individual/direct for this plan. Gary authorized publishing the
> plan to dev on 2026-10-07. Implementation has not been authorized; the
> approval hold on publishing an implementation remains in effect.

## Result

Use `$` to insert one result and `@` to splice a sequence. Apply this
consistently to macro signatures, named templates, anonymous macro values,
source quotations, computed meta calls, and compile-time Lisp slots.
Remove `@` and `@=` as matrix multiplication operators. Preserve matrix
multiplication as ordinary methods in the runtime and packages.

This is a complete source migration, not an alias-only addition. The final
branch uses the new syntax throughout maintained source, tests, examples,
tooling, and documentation. Native C ellipses are unaffected.

## Syntax contract

| Current source | Final source | Meaning |
| --- | --- | --- |
| `Expr $items...` | `Expr @items` | Declare a sequence parameter |
| `$items...` | `@items` | Splice a named syntax sequence |
| `$rows($items)...` | `@rows($items)` | Splice a computed meta/macro result |
| `$(some-form)...` | `@(some-form)` | Splice a compile-time Lisp result |
| `${expression}...` in a quotation | `@{expression}` | Splice an expression-valued quotation hole |
| `left @ right` | `left.matmul(right)` | Matrix multiplication |
| `left @= right` | explicit single-evaluation method update | Matrix multiplication and assignment |

The first four mappings and operator removal follow the conversation.
`@{expression}` is the plan's proposed completion for expression holes,
which exist on current dev. It reuses the existing List-splice spelling
and avoids leaving a suffix-based splice behind.

Example:

```x2c
macro Expression $call(Expr $callee, Expr @args) => $callee(@args);

macro Stmt $generated(Expr $value) {
  @rows($value)
  @(some-form)
}
```

These are syntax examples; the computed producers must be defined and
return syntax appropriate to their insertion positions.

- Keep singular `$name`, `$f(args)`, `$(form)`, `${expression}`, `$!` source
  quotations, macro invocation names, and `using $fresh` unchanged.
- A sequence parameter remains final and keeps its current element kind,
  inferred or annotated. Captured argument order and empty sequences stay
  unchanged. Signature names still share one namespace.
- `@name` means splicing only where the grammar accepts a sequence.
  `$name` still reads a captured sequence as one value inside compile-time
  Lisp, for example `@(list $items)`. Do not rewrite that reference to @.
- `@f(args)` uses the same callable resolution as `$f(args)`, including
  macro precedence and qualified names. Only insertion cardinality differs.
- A computed splice must produce the existing sequence representation.
  Preserve current expansion/binding order, hygiene, source locations,
  reverse macro recognition, and evaluation counts.
- Existing sequence roles remain argument, block, field, enumerator,
  Map entry, parameter, unit, catch, match row, and declarator row. Preserve
  current Captures and Type projection behavior; cardinality is not merely
  the fact that their underlying representation is a List.
- Reject old syntax sequence suffixes on the final branch. Do not reject
  ordinary C variadic `...`, Lisp atom data `...`, or historical examples
  explicitly labeled as old syntax.

## Quotation and literal sigils

Keep the existing mode boundaries. In ordinary code and macro-template
code, `@(` opens compile-time Lisp. In quoted List data, existing `@name`
and `@{expression}` retain runtime List-splice behavior. Do not silently
reinterpret `@(...)` in that data mode as compile-time Lisp.

Within quoted data, an outer `${...}` enters code grammar when a compile-time
splice is needed. Preserve the distinction between constructing template
syntax now and constructing a runtime collection in the generated program.
Arrays and Maps do not acquire general runtime splicing.

Nested definitions and quotations retain their own hole environments.
Preserve inner `$` and `@` holes through the outer template, using the
existing nested definition/quotation representation. Do not introduce a
second staging engine or raw token-to-source reparsing.

For literal sigils, use ordinary strings for character data and existing
quoted-atom escapes for atoms. Preserve percent-string dollar escaping.
Add examples proving that literal `$` and `@` survive template construction
and that inner holes expand at the intended layer. Do not invent `$$` or
`@@` staging operators as part of this rewrite. If an actual nested syntax
case cannot be expressed with existing structural boundaries, record that
case and resolve the escape rule with Gary before extending the design.

Indentation syntax stays supported. Its leading `@$decorator()` marker
remains a layout form; an `@producer(...)` splice line must reach the macro
parser rather than losing its leading sigil. Although omitted from the
earlier explanatory table, indentation syntax is not removed by this plan.

## Current owners and evidence

- `lib/scan.x`: operator recognition, including @ and @=.
- `lib/tokenizer.x`: code/literal/Lisp mode transitions, named references,
  bare operator atoms, and the leading @ layout rewrite.
- `src/macros.x`: `_signature_hole`, `_hole_name_token`,
  `try_parse_macro_slot`, `_meta_call_slot`, `_lisp_slot`, `_hole_slot`,
  `peek_macro_hole`, `after_hole`, `_quoted_hole`, `_expression_holes`,
  `_hole_splice`, and `_slot_splice`.
- Canonical `(macro-param ... (sequence ...))`, `(macro-bind ...)`, and
  `(macro-slot SPLICE ...)` already represent the required distinctions.
  Reuse them and the ordinary `bind_syntax` operations.
- `src/expressions.x`, `src/parse.x`, `src/statements.x`, and
  `src/literals.x`: syntax-position dispatch and embedded template forms.
- `src/operator-ledger.x`: the authoritative row for @ precedence, @=
  assignment, and matmul protocol mapping. `src/ast.x` and `src/protocol.x`
  declare its projections. `lib/varops.x`: dynamic operator dispatch.
- `lib/protocols.x`, `lib/common.x`, `lib/dispatch.x`: ordinary matmul
  witnesses and runtime methods. Preserve useful method capability rather
  than deleting matrix multiplication with its punctuation.
- Both `packages/blis` and `packages/torch` use matrix punctuation.
- `etc/builtin-macros.x`, `etc/lisp-bindings.x`, `src/`, `lib/`,
  and packages contain sequence signatures and computed splices.
- `etc/vsc-extension` contains TextMate syntax, semantic support, and grammar
  tests. Inspect commands, Lisp SDK data, docs tooling, and shipped templates
  for assumptions about sigils or operator spellings.

## Changes since the October 4 baseline

The syntax decision remains applicable, but these implementation boundaries
have changed. This revision is based on source inspection, not a new build.

| Current fact | Consequence for this rewrite |
| --- | --- |
| Compile-time definitions now live in ordinary `.x` modules | Migrate actual providers and their include interfaces; do not recreate `.xmacro` import machinery |
| Static definitions and retained include effects carry defining-source state | Preserve visibility, source order, lazy decode, and original bindings across transitive includes |
| Typed quotations `$!T{...}` and `$!(T){...}` construct typed expression code directly | Route @ holes through both typed and ordinary construction, without forcing expansion/binding |
| `$!Type{...}` and `$!Param{...}` construct syntax parts | Include parameter sequences and existing kind projections in the migration |
| `Definition.construction` can build quotations through cached List cells | Preserve constant-cell caching, hole value conversion, and retained fallback definitions |
| `src/operator-ledger.x` generates operator facts from one table | Delete its matrix row once instead of rebuilding separate operator tables |
| `src/linked-meta.x` is generated from shipped providers | Regenerate it; a migrated provider and its linked definition must agree |

The current source still uses the old sequence suffix. For example,
`unittest/compiler-fixtures/macro-quotation-typed.x` constructs
`$!(unsigned long){ f($lhs, $items...) }`. The intended form is
`$!(unsigned long){ f($lhs, @items) }`; the type and construction path stay
the same. `macro-quotation-param-hole.x` similarly forwards `$params...`
inside a generated function signature.

## Detailed code changes

### Scanner and layout

In `lib/tokenizer.x`, extend `_x2c_tokens` to recognize @ references and
adjacent `@(` before ordinary operator recognition. `_operator` pushes the
same `macro-lisp` mode for `@(` as for `$(`. Parentheses inside that mode
retain the existing nesting behavior. Preserve original token text and byte
positions; do not disguise @ source as a dollar token stream.

In `lib/scan.x`, @ stays a recognized punctuation character for sigils.
Removing matrix operators must not remove that character's token entirely.
Remove combined @= operator recognition from the final scanner. Ordinary
parser errors reject infix @ and @= once operator precedence is removed.

Quoted collections need a specific distinction. Current
`macro-array-sequence.x` uses `%[${10}, $items..., ${40}]`. Its replacement
is `%[${10}, @items, ${40}]` inside a macro template. `_lisp_prefix` currently
recognizes @ references only in List mode. Permit scanning the prefix in
quoted Array/Map modes so a registered template sequence can reach the
existing slot parser. The ordinary literal parser must still reject runtime
Array/Map splicing. Do not turn this migration into a new collection API.
Use the existing literal escape-to-code convention for computed producers
where the bare quoted grammar cannot express a code call. Preserve quoted
List's existing `@name(...)` data interpretation outside templates.

In `_Layout.end_statement`, strip leading @ only when it marks the existing
decorator spelling, including `@$name(...)`. An @ hole, @ meta call, or
`@(...)` Lisp splice retains its prefix. Update `_Layout.lisp_form` and
`_Layout.hole` for the new whole-line splice forms, including the hole after
a control header. Reuse the current insertion policy for holes that supply
complete statements; do not add an unconditional semicolon to a syntax
sequence. Brace and indentation forms must reach equivalent parser input.

### Macro signatures and slots

In `src/macros.x`, `_signature_hole` accepts an optional category before
either $ or @. Derive cardinality from the sigil and retain the existing
`macro-param` record. Keep `_using_hole` singular. Carry the prefix to
`peek_macro_hole`, `_parse_hole`, and `after_hole`; use the existing one
hole namespace and category inference.

Replace suffix lookahead in `_meta_call_slot`, `_lisp_slot`, `_hole_slot`,
and `_parse_lisp_slot` with prefix cardinality. `try_parse_macro_slot`
must recognize computed @ calls in every existing sequence role, not just
block statements. Reuse callable resolution and `macro-slot` output; do
not introduce a second meta-call evaluator. Preserve qualified macro names
whose components can be keywords, and macro-before-meta precedence.

The ordinary expression parser in `src/expressions.x` must allow these
prefixes to reach a sequence slot at argument boundaries without treating
them as binary operators. Inspect declaration, parameter, field, entry,
enumerator, catch, match-row, and top-level consumers in `src/parse.x`,
`src/statements.x`, `src/literals.x`, and `src/initializers.x`.
Keep one-statement positions distinct from block-item sequences. The newer
`macro Stmt ... => expression;` form remains a single statement; this
rewrite does not make every dollar call a splice.

After the authored corpus migrates, delete `_hole_splice`,
`_lisp_splice_follows`, and suffix consumption in `_slot_splice` where prefix
handling replaces their jobs. Retain any helper only if it still owns a
real grammar decision. Native varargs continue through their existing parser.

### Quotations and construction

Update `_expression_holes` to discover proposed `@{expression}` alongside
`${expression}` and record cardinality with the existing hidden local.
Retain left-to-right, once-only evaluation and position-keyed hole identity.
Preserve its exclusions for nested quotations and `case ${$macro(...)}`.

Change `_quoted_hole` to infer sequence cardinality from the opening prefix,
not from the token after the hole. Preserve `_quoted_role`'s current Param
handling and Type-local special case. Generalize `_expression_hole` naming
and arguments so they no longer imply that every opening sigil is dollar.

Both `Definition.construction` and typed construction must consume the same
hole descriptors. Inspect `_built_cells`, `_built_hole`,
`typed_construction`, `part_construction`, `written_keys`, `_typed_cells`,
and the landing/rebuild consumers.
Retain typed quotations' exact numeric literal families, String treatment,
identifier/member projections, and lack of binding or expansion transaction.
Do not route typed quotations through `bind_syntax` to share a call graph.
Nested typed construction still crosses the existing explicit `${...}`
boundary, rather than becoming directly legal inside a template.

Keep freeze/thaw and included-definition replay unchanged unless a source
syntax assumption requires an edit. A canonical hole's sequence bit already
survives these paths; no extra serialization field, cache version, or origin
tag is justified solely by changing its spelling.

### Matrix methods and generated providers

Remove the @/@=/matmul row in `src/operator-ledger.x` and obsolete
`_check_matmul`/dedicated operator diagnostics in `src/expressions.x` and
its report provider. Preserve `lib/protocols.x`, descriptor slots in
`lib/common.x`, and `lib/dispatch.x`'s ordinary matmul witness.

In `lib/varops.x`, remove @ from `Var.binary` and compound operator paths.
Retain `Var.matmul`: it currently passes @ to `_protocol_arithmetic` for
numeric fallback/error behavior. Keep this internal Symbol if it continues
to serve that method's error identity; removing source punctuation does not
require renaming an internal value. Give the method its existing unsupported
numeric behavior without keeping source-operator dispatch alive. Inspect
that helper before choosing a small change; do not add an operator registry.
BLIS/Torch typed and boxed methods must still invoke their existing callbacks.

`src/linked-meta.x` is explicitly generated by `tools/gen-linked-meta.sh`.
The build/bootstrap targets already invoke that generator. Use those targets
at transition boundaries; never edit the linked copy by hand. Also regenerate
`lib/x2c.x`, bootstrap C/H, and derived documentation through current targets.

### Corpus migration

Inventory signatures and syntax uses separately. Current candidates include
ordinary report/error providers, `lib/var-tags.x`, `lib/system-macros.x`,
`etc/builtin-macros.x`, `etc/lisp-bindings.x`, compiler quotations, command
sources, packages, fixtures, and editor samples. Search `.x` and `.xp`, plus
Lisp and maintained text templates. Generated files are outputs, not inputs
to the rewrite.

Classify each occurrence by the scanner mode and grammar position. Rewrite
the defining prefix and each splice use together. Preserve `$sequence`
when Lisp receives a sequence as one argument. Leave literal ellipsis,
native C variadics, shell expansion, reader `,@`, runtime List splicing,
and archive records untouched. Review all changes to `${...}` and quoted
Array templates individually. Any temporary migration script stays in /tmp
or .context and adds no shipped transformation framework.

## Implementation

1. Establish the working seed from this branch's shipped bootstrap with
   `mkdir -p debug && make build-safe >debug/bootstrap.log 2>&1`.
   Inventory live syntax uses by parser context. Include expression holes,
   reverse macro patterns, sequence projections, and indentation files.
   Exclude unrelated shell dollars, strings, comments, and historical records.
2. Add prefix-based signature and splice parsing while the old source still
   builds. Share dollar/at parsing where it owns the same grammar; pass the
   cardinality to the existing canonical forms. Extend tokenizer modes for
   `@(` and code references without changing quoted data mode semantics.
   Fix the layout marker distinction in the same connected change.
   Complete typed/part quotation construction, expression-hole discovery,
   quoted Array template slots, and ordinary included/static definitions
   before any self-hosted corpus rewrite. Keep old suffix support and matrix
   punctuation through this private transition.
3. Verify the new syntax with focused examples on the old corpus. Regenerate
   bootstrap through `make bootstrap-refresh` when needed, and rebuild a
   seed that can consume the new syntax before migrating self-hosted source.
   This is a private transition, not an intermediate publication or gate.
   Use a new-form copy of the `_operator_cases` splice from
   `src/operator-ledger.x` as one focused producer/consumer probe. Confirm
   shipped provider hashes and generated linked definitions agree at the
   refresh. Preserve the working intermediate seed until the migrated source
   compiles; do not rely on an old binary after replacing its source modules.
4. Migrate the complete authored corpus with a token/context-aware rewrite
   and manual review. Convert declarations, splices, computed calls, source
   quotations, generated templates, and macro-recognition examples together.
   Preserve `$sequence` reads in Lisp. Never use unrestricted text replacement.
5. Remove matrix punctuation from scanning, precedence, protocol mappings,
   dynamic operator cases, diagnostics, and tooling. Retain ordinary matmul
   methods and usable conformance. Migrate package examples/tests to methods.
   For compound updates preserve one evaluation of an addressable destination,
   operand order guarantees, and assignment only after successful computation.
6. Remove transitional support for old syntax splices and obsolete suffix
   parsing. Inspect residual `...` and @ operator references individually.
   Keep native varargs, intentional quoted data, List splices, decorators,
   and explicit historical documentation.
7. Update the language reference, macro/meta guides, package documentation,
   editor grammars/tests, agent references, and maintained syntax examples.
   Regenerate derived documentation through its documented targets.
   Preserve the saved
   `.context/x2c-c-differences-starting-inventory.md` as a baseline record;
   link the new contract rather than rewriting history.
8. Run focused verification, review and fix the completed authored diff,
   then perform final bootstrap regeneration and self-host verification.
   Review all generated deltas. Produce the local review result and stop
   under Gary's approval hold. Do not create a PR or merge to dev.

## Verification

Use existing scanner/tokenizer suites and compiler-fixture mechanisms. Add
or revise focused cases within those mechanisms; add no recurring gate.

| Boundary | Existing anchors to migrate or extend |
| --- | --- |
| Scanner, mode transitions, layout | `unittest/test-scan.x`, `test-tokenizer.x`; current indentation fixtures |
| Signatures and code slots | `macro-sequences`, `macro-slot-recognition`, `macro-array-sequence` |
| Typed expression construction | `macro-quotation-typed`, `macro-quotation-typed-values`, `macro-quotation-typed-function-type` |
| Preserved typed restrictions | `macro-quotation-typed-declaration`, `macro-quotation-typed-nested` |
| Type and parameter syntax parts | `macro-quotation-param-hole`, `macro-quotation-param-named`, current Type quotation fixtures |
| Computed hole order/cardinality | `macro-quotation-expression-holes`, `macro-quotation-scalar-splice` |
| Include state and visibility | `ordinary-interface-cold`, `ordinary-interface-warm`, `ordinary-interface-static-macro`, `ordinary-interface-static-keyword`, `ordinary-interface-meta-order-warm` |
| Retained declaration producers | `declaration-macro-retained-names`, `header-include-after-source`, ordinary-interface provider fixtures |
| Matrix methods and rejection | `protocol-operator-matmul`, `protocol-operator-matmul-missing`, BLIS/Torch existing tests |
| Macro runtime and shipped forms | `unittest/test-macros.x`, `test-system-macros.x` |

Fixture names above refer to `unittest/compiler-fixtures/<name>.x`.
Run individual cases with the current checked-in runner, for example:

```sh
unittest/compiler-fixtures/run.sh check --fixture macro-sequences
unittest/compiler-fixtures/run.sh check --fixture macro-array-sequence
unittest/compiler-fixtures/run.sh check --fixture macro-quotation-typed
unittest/compiler-fixtures/run.sh check --fixture macro-quotation-expression-holes
```

For an intentional change to a named expectation, use that runner's `update`
mode and review its owned sidecars. Do not bulk-update unrelated failures.
These commands are implementation checks to run later; this plan refresh
does not claim they passed on the new syntax.

- Named sequence declarations/use, empty/multiple elements, annotations and
  inferred kinds, all existing sequence roles, aliases, and local macros.
- Computed @ calls and Lisp slots: expansion once, insertion order, qualified
  names, empty results, and the same canonical binding as prior forms.
- Source quotations: `@name`, proposed `@{expression}`, multiple holes,
  nested quotes/definitions, literal sigils, and reverse macro recognition.
- Include/replay: migrated nonstatic definitions cross ordinary/transitive
  includes while static definitions remain local. Compare cold and warm
  source paths and retain exactly-once declaration production. Preserve
  `src/compiler.x::_retain_bundle` and `replay_declaration_source` contracts;
  do not compensate for a parser change by executing a retained producer twice.
- Data versus code modes: unchanged runtime `$` insertion and @ List splice,
  nested literals, dollar references to whole sequences within Lisp, and
  `@(...)` data-mode behavior.
- Indentation: decorator markers versus at-prefixed splice statements,
  continuations, and layout-produced punctuation.
- Native C varargs and singular macro/meta/Lisp forms remain accepted.
- Old syntax splices and removed matrix punctuation are rejected without
  accidental acceptance as a different program. Reuse existing category,
  cardinality, and placement errors rather than creating a parallel validator.
- Matrix method replacements retain results in BLIS and Torch. Network or
  package prerequisites are reported as package coverage gaps if unavailable.
- Editor syntax tests reflect the parser's actual accepted forms.

Review intentional fixture expectation changes through the existing update
workflow; normal fixture checking does not rewrite expectations. Use focused
generated-C inspection for hygiene, order, and one-time evaluation. Final
code validation uses `tools/gate-state.py ensure agent-pr-check`, which owns
final artifact refresh and self-host comparison. Do not add or independently
repeat its broad components merely for delivery. Relevant performance work
follows `agents/performance-checkpoints.md` before eventual publication; no
performance claim is made by this planning work.

## Compatibility and approval

The final syntax is intentionally incompatible with sequence suffixes and
matrix operator punctuation. Existing runtime data literals and singular
forms retain their meanings. Temporary dual parsing exists only to cross the
self-host bootstrap transition and is removed before final validation.

This plan proposes `@{expression}` as the remaining expression-hole spelling.
No additional escape syntax is selected. Implementation is not authorized by
this planning-only turn. Approval of implementation does not lift the separate
hold on a PR, merge, or publication to dev unless Gary says so.

## Plan review

- Signature parsing already establishes hole kind and cardinality; slot
  grammar already establishes legal sequence positions. Preserve those
  boundaries and use their facts without another validation traversal.
- Reuse canonical parameter, binding, and splice-slot representations,
  nested template environments, literal modes, and ordinary syntax binding.
  Delete suffix-specific consumers and matrix punctuation paths. A shared
  sigil parser is justified only where it replaces duplicate source parsing.
- The change composes x2c's existing List splice syntax with its macro grammar.
  It adds no new AST family, source reparser, cache, origin tracking, framework,
  or independent staging system.
- No new validator or dedicated diagnostic is proposed. Focused rejection
  fixtures protect deliberate removal of old syntax and existing kind,
  cardinality, and placement contracts; nested/mode fixtures protect against
  wrong code or expansion at the wrong layer. Existing matching and binding
  continue to accept structurally valid constructed ASTs from any producer.
