# x2c lint, format, and compiler-backed source tools

> Status: needs author scoping - re-evaluated 2026-09-24 against `dev` at
> `29326dbd`; no phase implemented. This plan now also owns the
> compiler-backed rewrite from [x2c-scripting-ports](x2c-scripting-ports.md)
> ("Rewrite on the compiler instead of translating"), including catalog
> item [C09](consolidation-catalog-f28fc36.md#c09-remove-docs-independent-declarationmacro-interpretation).
> The 2026-09-17 design decided three things that still stand: lint ships
> as an `x2c lint` subcommand, it stays optional until it replaces the
> Python analyzers, and the class ceiling gets a diagnostic rather than a
> runtime change. The decisions below are open.

## The result

Every tool that reads x2c source reads what the compiler parsed. No
regular-expression parser for x2c survives in the repository. Two
consumers share one compiler surface:

- `x2c lint`, in the compiler, for rules that need the bound, typed AST
  or the retained token stream, and later `x2c fmt --check`.
- x2c scripts in the indentation syntax (`#pragma indent`) for the doc
  generators, the module catalog, repository metrics, and the bloat and
  overengineering reports. They read a compiler projection and never
  parse source themselves.

## What is deleted

| File | Lines | Replaced by |
| --- | --- | --- |
| `tools/x2c_source.py` + `tools/test-x2c-source.py` | 1,173 | projection |
| `tools/x2c_symbols.py` | 538 | `.xi` rows / projection |
| `tools/gen-api-reference.py` | 1,251 | script |
| `tools/gen-module-catalog.py` | 134 | script |
| `tools/repo-metrics.py` | 387 | script |
| `tools/audit-source-bloat.py` | 860 | lint structural rules |
| `clean-x2c-source/scripts/` (`source_style.py`, test, `audit-source.sh`) | ~790 | lint token rules |
| `find-comment-slop/scripts/` (analyzer + test) | 767 | lint comment rules |
| `find-redundant-validation/scripts/` (analyzer + test) | 1,479 | lint validation rules |
| `find-x2c-overengineering/scripts/` (analyzer + test) | 575 | script |

About 8,070 lines of Python and shell. Estimated hand-authored `.x` added:
about 200 in the compiler projection, 1,800 for the lint engine and rules,
and 1,100 for the scripts, about 3,100 in total. Net about -5,000 lines.
These are estimates; each phase records its measured delta.

## What the compiler already provides

Checked on `29326dbd`:

- **Tokens with trivia.** `lib/tokenizer.x` keeps `<space>` and `<comment>`
  tokens with line, column, length, and position. `x2c translate
  --dump-tokens` prints them. Indented units add synthesized `{`, `}` and
  `;` tokens, so a token rule must tell them from written ones.
- **Parsed and typed AST.** `--dump-ast`, `--dump-transforms`, and
  in-process `Frontend` and `ParsedUnit`, which `tools/x2c-graph` links
  from `builds/0` objects. Types, bindings, and receivers are resolved.
- **Source syntax with macro calls kept.** `--dump-source-ast` (added in
  `d12a4b06`, experimental) wraps each definition as `(api-source line doc
  form)`.
- **Selected public definitions.** Since `f1228d90` every `.xi` interface
  carries a row per public, non-static function the compiler selected,
  Unit-macro and foreign-alias products included: name, display name
  (`Owner.member`), signature, parameter names, line, and doc comment.
  `x2c_symbols.py` already reads them, and
  `unittest/probes/run-public-definition-projection.sh` covers them. This
  is most of C09's "required design".
- **Diagnostics.** The entry shape, JSON Lines writer, caret renderer,
  `--fatal-warnings`, and the editor's byte-span reply.

## What is missing

1. **Static and private definitions.** The `.xi` rows cover public
   functions only. Metrics, the catalog, bloat, and overengineering need
   every definition, including types and macros.
2. **End spans.** No AST node records where it ends. Function length,
   body spans, and comment attachment need a half-open token range at
   least for definitions and statements.
3. **Module prose.** The file header comment is not projected;
   `module_summary` and `module_prose` still scan for it.
4. **A stable, documented projection.** `--dump-source-ast` is labelled
   experimental and prints only positions and docs. One request flag
   (proposed `--dump-definitions`) should print each selected definition
   with kind, name, display name, static flag, origin (source, Unit macro,
   foreign alias), start and end position, doc, and the module prose. The
   `.xi` rows become a filtered subset of the same function, so there is
   one producer.
5. **Warning codes.** The unnecessary-cast and unnecessary-converter
   warnings and three others still report the generic `<warning>`, so
   they cannot be grouped, suppressed, or deduplicated by code.

Nothing here needs a second parser, a CST, or a pretty-printer.

## Architecture recommendation

**Both, split by what a rule needs.** Rules that read types, bindings, or
the retained token stream run in the compiler as `x2c lint`, because an
external script over a text dump would need a typed dump that does not
exist and would duplicate the frontend. Everything that needs only
definitions, spans, and docs becomes a script over `--dump-definitions`.
`src/lint.x` and the projection share one definition walk, which is the
single module; the `.xi` writer, `--dump-definitions`, and lint all call
it.

A lint that is only a script (the alternative) is smaller in the compiler
but can implement only the token and comment families: the idiom rules
(`in`, `.` for `->`, `$auto`, bare literals) need receiver types. A lint
that is only a subcommand would move the doc generators into the compiler
binary, which is house tooling on the public surface.

## Tiers and rules

The three tiers from the 2026-09-17 design hold unchanged. A **compiler
warning** must be universal, free on an existing walk, near-zero false
positive, and have a byte-identical fix. A **lint finding** is correct code
that is not this repository's idiom, opt-in, proven by diffing generated
C. A **format change** changes only whitespace tokens, checked by comparing
the non-trivia token sequence, the same proof `tools/indent-convert` used
for the indentation conversion.

The rule inventory holds: `->` where `.` works, percent literals where a
bare literal means the same, `.contains(x)` for `x in c`, acquire and
`defer` for `$auto`, `Type.method(x)`, `{ return e; }` for `=>`,
`String.new("lit")` and `Array.new()` for literals, field-by-field
initialization, ungrouped declarations, and the comment, validation, and
bloat families. Each rule keeps the 2026-09-17 obligations: census,
classify until the keeps are stated predicates, rewrite and diff the
generated C, cite archived decisions, one positive fixture and one
negative fixture per keep predicate, and `literate-lisp.x` scores zero.
The counts (178 removable arrows, zero `$auto` in `packages/`) are from
2026-09-17 and are recounted by each rule's census before it ships.

Findings reuse the diagnostics entry with a `<lint>` severity and a
disposition (`SAFE`, `CHANGES-FAILURE-PATH`, `NEEDS-MORE`, `KEEP`,
`PREVIOUSLY-DEFERRED`). Suppression is a path-glob list in
`etc/lint.xlisp` and `// lint: allow <code> - reason`. `--fix` applies
textual edits and refuses to write when the generated C changes. Rules
are one static table; `x2c lint --rules` prints it. Four survey findings
remain compiler bugs for `fix-x2c-bug`, not rules.

## Changes on dev since 2026-09-17

- **Indentation syntax landed** (`7571ff7a`, `cf0b9a84`, 2026-09-24).
  There is no separate branch to wait for. The script tools are already
  converted, so the new scripts start in `#pragma indent` form. Lint token
  rules and the formatter must handle `.xp` and `#pragma indent` units:
  brace, `else`, and semicolon rules do not apply there, and the
  formatter's indentation is structural in them.
- **Public definition projection** (`f1228d90`) covers most of C09.
- **`--dump-source-ast`** (`d12a4b06`) is the start of the projection.
- **`--fatal-warnings`** exists as a hidden translate option
  (`90ac13b4`), so a warning-tier rule can already fail a build that asks.
- The dogfooding campaign is archived; lint is its remaining backlog.
- `find-x2c-overengineering` now also imports `x2c_source.py`, which makes
  six importers, not five.

## Phasing

0. Give the five generic warnings codes.
1. Shared definition walk and `--dump-definitions` with end spans, static
   definitions, and module prose. The `.xi` writer calls the same walk.
   Probe: the new output lists every definition `x2c_source.py` finds on
   `src/` and `lib/`, diffed as name and line sets.
2. Port `gen-api-reference`, `gen-module-catalog`, and `repo-metrics` to
   scripts over the projection. Generated docs must be byte-identical.
   Delete `x2c_source.py`'s doc paths and `x2c_symbols.py`. This completes
   C09.
3. `x2c lint` engine and token rules; parity with `source_style.py` and
   `audit-source.sh`; delete them; measure the binary-size delta.
4. Identical-translation idiom rules with `--fix`, one cleanup delivery per
   family.
5. Comment rules; parity; delete `comment_slop.py`; fold the skill into
   `clean-x2c-source`.
6. Structural and validation rules; parity with `audit-source-bloat.py` and
   `redundant_validation.py`; port the overengineering report to a script;
   delete the rest of `x2c_source.py`.
7. Editor lint kind and fixes; then `fmt --check`, token-only.

Phases 1 and 2 are worth shipping alone: they end C09 and remove about
2,500 lines of Python. Phase 3 needs its own approval under decision 1.

## Process ceiling

No gate is added. `precommit`, `sanity-check`, and `agent-pr-check` are
unchanged. `make doc-generate` switches from Python to scripts at Phase 2,
at no added cost. Lint fixtures live with the tool, not in
`unittest/compiler-fixtures/`.

## What this does not build

No rule DSL or plugin system. No lint pass on the translate path. No
pretty-printer or CST. No autofix for structural rules or comments. No
class-conversion autofix. No `not in` syntax. No LSP. No heuristic matcher
inside the new tools.

## Decisions for Gary

1. **Architecture.** Recommend both: `x2c lint` in the compiler for typed
   and token rules, scripts over a compiler projection for docs and
   metrics, one shared definition walk. This reaffirms the 2026-09-17
   subcommand decision.
2. **Projection form.** Recommend a documented `--dump-definitions`
   translate option that replaces the experimental `--dump-source-ast`,
   rather than enlarging `.xi` files, which every build writes.
3. **Order.** Recommend Phases 1 and 2 (C09 and the doc generators)
   before any lint phase, because they build the shared walk and delete
   the keystone importers first.
4. **Rule families by default.** Recommend language-level rules on by
   default and repository-policy rules selected explicitly, as designed.
5. **Run policy.** Recommend lint stays optional, invoked by the
   `clean-x2c-source` skill. A gate would need an equal-cost removal under
   the process ceiling, and this plan does not propose one.
