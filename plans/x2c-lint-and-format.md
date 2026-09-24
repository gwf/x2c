# x2c lint, format, and compiler-backed source tools

> Status: active - Gary accepted all six decisions on 2026-09-24. Re-evaluated 2026-09-24 against `dev` at
> `29326dbd`; lint placement measured on `76cead06`. Phases 0 through 3
> are implemented; see [Progress](#progress). The completed linter moved
> into experimental `commands/lint` in `9b31112e` under the
> [external commands](archive/external-commands.md) plan.
> This plan now also owns the compiler-backed rewrite from
> [x2c-scripting-ports](x2c-scripting-ports.md) ("Rewrite on the compiler
> instead of translating"), including catalog item
> [C09](consolidation-catalog-f28fc36.md#c09-remove-docs-independent-declarationmacro-interpretation).
> The 2026-09-17 design decided that lint stays optional until it replaces
> the Python analyzers and that the class ceiling gets a diagnostic rather
> than a runtime change. Its third decision, lint as an `x2c lint`
> subcommand, is reopened by decision 1 below.

## The result

Every tool that reads x2c source reads what the compiler parsed. No
regular-expression parser for x2c survives in the repository. Two
consumers share one compiler surface:

- `x2c lint`, a separate executable in `commands/lint/` that links the
  compiler's objects, for rules that need the bound, typed AST or the
  retained token stream, and later `fmt --check`.
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

## Lint placement: in the compiler or linked beside it

Measured on `76cead06` (M4 Max host, load average 16-35 from other agents).
The stand-in for 1,800 lines of lint was the four `tools/x2c-graph`
analysis modules (`lifetime.x`, `loop-allocations.x`, `clones.x`,
`targets.x`, 1,881 lines of match-heavy AST walks) copied into `src/` and
included from `main.x`, on a local throwaway branch that was deleted.

### Hand-authored `.x` in the compiler

| Option | `src/` lines | Change |
| --- | --- | --- |
| Today | 43,590 | - |
| Lint inside (walk 200 + lint 1,800) | about 45,590 | +4.6% |
| Separate tool (walk 200 only) | about 43,790 | +0.5% |

The separate tool puts its 1,800 lines in `tools/x2c-lint/`, as
`tools/x2c-graph` does with its 5,682.

### Cost of lint inside the compiler

| Measure | Base | With 1,881 lines | Kind |
| --- | --- | --- | --- |
| Binary size | 2,534,256 B | 2,625,920 B (+3.6%) | measured |
| `bootstrap/src` C added | - | 171 KB in 4 files | measured |
| `--version` instructions | 51.3 M | 52.7 M (+1.35 M, +2.6%) | measured |
| `--version` time | 10 ms | 9-10 ms; +0.15 ms from cycles | measured |
| Trivial translate | 56-61 ms | 56 ms | measured, within noise |
| Trivial translate instructions | 768 M | +1.35 M (+0.2%) | inferred from `--version` |
| `lib/string.x` translate | 184 ms | 183 ms | measured, within noise |
| `src/expressions.x` translate | 510 ms | 493 ms | measured, within noise |
| One stage, cycles (median of 3) | 41.6 G, 40.6 G | 43.3 G, 39.6 G | measured, within 4-5% noise |
| One stage, cycles | - | +2.4% | inferred, proportional to lines |
| One stage wall, `-j16` | 6.5 s | 6.9 s | measured, one sample each |
| `make bootstrap-refresh` | - | 21 s | measured |
| `make build` after editing the module | - | 5.5 s | measured |

Startup work that grows with the compiler: every run hashes the whole
executable for `x2c_compiler_identity` (`src/utils.x`), and each module's
`_file_init_` constructor builds its literal and pattern constants.
`bootstrap/src` has 13,818 such assignments for 43,590 lines, 0.32 per line;
match-heavy modules reach 0.5-0.6, so lint adds about 1,000. Registered Lisp
is unchanged. Both costs appear in the `--version` delta above and are
under 0.2 ms.

Lint is off during translation in both options, so per-file compile time
does not change.

The larger cost is the edit loop. A lint rule edit is a compiler edit:

- The stage-0 compiler's identity changes, so the `.xi` interfaces the
  previous compiler wrote no longer validate. Until bootstrap refresh, every
  stage-0 translate collects `lib/meta.x` cold. Measured: trivial translate
  46 ms at the fixpoint, 360 ms after one module edit; `src/expressions.x`
  510 ms to 1,030 ms.
- Publication needs the full `agent-pr-check` path: bootstrap refresh, safe
  rebuild, stages, and the self-host comparison, plus a 171 KB
  `bootstrap/` delta whenever the rules change.

### Cost of a separate tool

A compiler library already exists in practice. `tools/x2c-graph/Makefile`
archives `builds/0/src/*.o` without `main.o` into `libx2c-dev.a` and links
it with its own `.x` files, which include `src/frontend.x` directly. No
installed library or stable API exists; `docs/src/internals/compiler-api/`
marks the API provisional.

Proof: `unittest/build/lintproof/lintproof.x` (45 lines, not committed)
calls `Frontend.new`, `preload_macro_libraries`, and `Frontend.open`,
matches `%(function *)` over `parsed.ast`, and reads the token array through
`parsed.compiler.tokenizer`. Over `src/*.x` it reported 2,067 functions,
5,296 typed `->` nodes, and 28 written `->` tokens. It worked on the first
build after one pattern fix.

| Measure | Value | Kind |
| --- | --- | --- |
| Archive of 36 compiler objects | 2.8-2.9 MB, 20-40 ms | measured |
| Proof binary | 2.0 MB | measured |
| Proof build (translate, compile, link) | 0.3-0.8 s | measured |
| `x2c-graph` cold build (5,682 lines) | 1.9 s | measured |
| `x2c-graph` rebuild after touching a module | 0.5 s | measured |
| Compiler size, startup, stage builds | unchanged | measured by construction |

The tool relinks whenever `make build` rebuilds the compiler, because its
archive target depends on the compiler build, and it translates against the
current `src/` headers, so type and struct changes fail its build. AST
shape changes do not: a stale `match` pattern stops matching silently. The
guard is a small fixture set per rule run by the tool's own test target, as
`tools/x2c-graph/tests/ast-parity.x` does. Nothing in a gate builds
`x2c-graph` today; an ungated lint would drift the same way.

Packaging: installs ship neither compiler objects nor `src/`. A repository
tool needs no packaging. Shipping lint to users would add a second
executable of about 2 MB, or the archive and headers, and an `x2c lint`
subcommand that runs it.

### Rule access

| Rule family | Needs | Linked tool |
| --- | --- | --- |
| `.` for `->` | written tokens and receiver types; the typed AST rewrites `.` through pointers to `->` (5,296 typed vs 28 written in `src/`) | same |
| `x in c`, `$auto`, `Type.method(x)`, `=>`, literals, grouped declarations, initialization | bound, typed AST | same |
| Percent vs bare literal | typed AST plus tokens | same |
| Brace, comment, blank-line, whitespace | tokens with trivia | same |
| Validation and bloat families | typed AST, non-returning facts, spans | same |

A linked tool runs the same `Frontend` in the same process, so it sees
every fact a subcommand would. What it cannot do is add a hook inside a
compiler pass; no listed rule needs one.

## Architecture recommendation

**A separate `x2c-lint` executable in `tools/x2c-lint/`, built like
`x2c-graph` from the compiler objects, plus the shared definition walk and
`--dump-definitions` projection in the compiler for the scripts.** The
runtime costs of lint in the compiler are small, under 0.2 ms at startup and
about 2.4% per stage build. The deciding costs are the 4.6% growth of
hand-authored compiler source for house tooling, and an edit loop where
every rule change is a compiler change with bootstrap refresh, cold stage-0
translation, and the full publication gate. The tool loses no rule access.

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
are one static table; `x2c-lint --rules` prints it. Four survey findings
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
3. `tools/x2c-lint` engine and token rules, built from the compiler
   archive with a `test` target over its fixtures; parity with
   `source_style.py` and `audit-source.sh`; delete them.
4. Identical-translation idiom rules with `--fix`, one cleanup delivery per
   family.
5. Comment rules; parity; delete `comment_slop.py`; fold the skill into
   `clean-x2c-source`.
6. Structural and validation rules; parity with `audit-source-bloat.py` and
   `redundant_validation.py`; port the overengineering report to a script;
   delete the rest of `x2c_source.py`.
7. Editor lint kind and fixes, if decision 6 ships lint to users; then
   `fmt --check`, token-only.

8. Follow-up after the first version, approved by Gary on 2026-09-24:
   `x2c-lint` gains an option that prints its findings as x2c list
   literals, which the compiler reads without a JSON step. JSON output for
   third-party tools can be added beside it later. With that in place,
   `x2c lint` becomes a thin compiler entry point, as a subcommand or
   directive, that runs the linter on a source file and reads the result.
   The compiler can then report findings or raise them to errors during a
   build. This is a compiler change, so it waits until the linter exists.

Phases 1 and 2 are worth shipping alone: they end C09 and remove about
2,500 lines of Python. Phase 3 needs its own approval under decision 1.

## Progress

**Phase 0, 2026-09-24.** The unnecessary-cast and unnecessary-converter
warnings report `conversion`, and the protocol-binder warning reports
`shadow`. The two native-module `meta` warnings in `src/macros.x` still
report `warning`; that file was reserved by another session, so they wait.

**Phase 1, 2026-09-24.** `Compiler.definition_rows` in `src/generate.x` is
the one definition walk. The `.xi` writer filters its rows to public
functions, and `x2c translate --dump-definitions` prints every row with its
span, static flag, origin, doc, source text, and the module comment. The
parser records each authored declarator's token range, decorator targets
included, and the top-level parse loop records each form's span. The option
replaced `--dump-source-ast`; the source-syntax parse mode behind the old
option is now unreachable and is removed in a follow-up, because part of it
is in `src/macros.x`. Source delta: 210 lines added, 50 removed.

Probe against `x2c_source.py` on `src/` and `lib/`, as name and line sets
with static functions included: 4,784 of its 4,816 functions and all 171
public types agree. The rest are known differences, none a projection gap:

- 17 foreign aliases in `lib/lisp.x` report the `$x2c.foreign.alias` line,
  one above the declarator the regex found.
- 8 static helpers inside Unit macros (`load`, `store`, `next`,
  `record_compare` and relatives) carry hygienic `_x2c_macro_*` names, one
  per expansion, where the regex reported the template's name once.
- 7 compile-time-only `meta` functions in `lib/meta.x` are not part of the
  translated unit.
- The projection also lists 15 static definitions the regex missed:
  `_stat` in `lib/path.x` and the typed-array `_core_*` helpers.
- `MatchCache` and `MatchLease` in `lib/match.x` follow `#pragma public`;
  the regex stopped at the first `#pragma private`.

**Phase 2, 2026-09-24. C09 is complete.** `tools/gen-api-reference`,
`tools/gen-module-catalog`, and `tools/repo-metrics` are indentation-syntax
x2c scripts. The two generators share `tools/definitions.x`, which runs
`--dump-definitions` over every unit in one batch per processor; each dump
now starts with `(unit PATH)` so a batch can be split. `x2c_symbols.py`,
the three Python generators, `test-x2c-source.py`, and the documentation
half of `x2c_source.py` are deleted: 3,088 lines of Python. The remaining
397 lines of `x2c_source.py` serve `audit-source-bloat.py` and the
redundant-validation and overengineering analyzers until Phase 6. The
expression-bodied probe's Python AST reader became
`unittest/probes/expression-bodied-functions/compare-ast`. Scripts added:
1,606 lines.

With the generator banner changed to `make doc-generate`, the 86 pages,
`SUMMARY.md`, and the module catalog were byte-identical to the Python
output on the same tree. Two behaviors are kept for that parity and are
worth revisiting: public types still stop at the first `#pragma private`,
which hides the documented-in-prose but `/*`-commented `MatchCache` and
`MatchLease`; and a Unit-macro product's signature is still spelled from its
type. The stale-interface and signature cross-checks against `.xi` files
are gone, because pages and compiler now read the same walk. Each
generator's check went from about 3.1-3.6 s on one core to about 2 s, using
about 15 s of processor time across cores. The Pages workflow builds the
compiler, because the landing page runs `tools/repo-metrics`.

**Phase 3, 2026-09-24.** `tools/x2c-lint` is an indentation-syntax tool of
1,017 lines that links `builds/0/libx2c-dev.a` and the embedded identity
from `make commands`; `make -C tools/x2c-lint test` checks 49 expected lines
over its fixtures. It has 26 rules in one table, printed by `--rules`: the
language rules (`forward-declaration`, `same-file-forward-declaration`,
`negated-is`) run by default, and `--all` or `--rule CODE` selects the
style rules. Token rules read a fresh `Tokenizer.scan` of the file with the
indentation syntax's zero-width tokens dropped; the prototype and subject
rules read the parsed unit and `Compiler.definition_rows`. The compiler
change is one line: `_record_definition_span` also keys each top-level
`declare` node, so a prototype has a span. `source_style.py`, its test, and
`audit-source.sh` are deleted (907 lines). Not carried over: the file
metrics `audit-source.sh` printed (lines, bytes, includes, comment-start
and line-comment counts, maximum width), which `wc` and the per-line rules
replace.

Parity on `src/` and `lib/` (94 units), as file, line, and category sets
with the old names:

| Category | Old | New | Old only | New only |
| --- | --- | --- | --- | --- |
| forward (src) | 26 | 26 | 0 | 0 |
| same-file forward | 6 | 103 | 0 | 97 |
| runtime forward | 271 | 157 | 114 | 0 |
| wrapped opening line | 164 | 161 | 18 | 15 |
| continuation indent | 11 | 22 | 0 | 11 |
| standalone closer | 9 | 16 | 0 | 7 |
| horizontal form | 145 | 159 | 0 | 14 |
| short control flow | 124 | 151 | 0 | 27 |
| subject parameter name | 11 | 12 | 0 | 1 |
| negated `is` | 5 | 3 | 2 | 0 |
| decorated ruler | 7 (count) | 7 | 0 | 0 |
| all other categories | 209 | 209 | 0 | 0 |

Every difference is explained. Of the 114 runtime prototypes, 97 declare
functions the unit defines through a Unit macro, which the regex could not
see, and 17 are `$x2c.foreign.alias` declarations, which are not
prototypes. The 18 wrapped lines were `c.expect(<(>)`, where the regex read
the Symbol as a parenthesis. The new wrapping findings are calls on
receiver chains such as `a.b.c(` and `x().y(`, which the old name scan
skipped, code inside `${...}` in quoted forms, and signatures after a
`<(>` that misaligned the old parenthesis pairs. The 27 short control
flows are `foreach` headers. The subject finding is `Lisp.eval_file`, also
behind a misaligned pair. The 2 negated `is` findings were `%!(x) => x is`
lambdas. Rulers were only counted before and are now listed. On the
fixtures, the old scripts and the tool agree on every category except the
same two false-positive kinds. The tool takes 5.4 s over the corpus,
parsing every unit, against 10.6 s for the scripts; a cold build takes
1.9 s after `make commands`.

## Process ceiling

No gate is added. `precommit`, `sanity-check`, and `agent-pr-check` are
unchanged. `make doc-generate` switches from Python to scripts at Phase 2,
at no added cost. Lint fixtures live with the tool, not in
`unittest/compiler-fixtures/`. Building and testing `tools/x2c-lint` in
`check` would be a new recurring cost; see decision 5.

## What this does not build

No rule DSL or plugin system. No lint pass on the translate path. No
pretty-printer or CST. No autofix for structural rules or comments. No
class-conversion autofix. No `not in` syntax. No LSP. No heuristic matcher
inside the new tools.

## Decisions

Gary accepted all six recommendations below on 2026-09-24.

1. **Lint placement.** Recommend a separate `tools/x2c-lint` executable
   linking the compiler objects, as `x2c-graph` does. This replaces the
   2026-09-17 `x2c lint` subcommand decision. It keeps about 1,800 lines out
   of `src/` and keeps rule edits out of bootstrap refresh. The later
   [external commands](archive/external-commands.md) plan moved the
   standalone tool to `commands/lint` as an experimental command;
   it remains optional and is not installed.
2. **Projection form.** Recommend a documented `--dump-definitions`
   translate option that replaces the experimental `--dump-source-ast`,
   rather than enlarging `.xi` files, which every build writes. It stays in
   the compiler because the `.xi` writer shares its walk.
3. **Order.** Recommend Phases 1 and 2 (C09 and the doc generators)
   before any lint phase, because they build the shared walk and delete
   the keystone importers first.
4. **Rule families by default.** Recommend language-level rules on by
   default and repository-policy rules selected explicitly, as designed.
5. **Run policy.** Recommend lint stays optional, invoked by the
   `clean-x2c-source` skill, and its build and fixtures stay out of gates.
   Drift then shows up when the skill runs, as with `x2c-graph`. Gating
   it would need an equal-cost removal under the process ceiling.
6. **Distribution.** Lint remains experimental in the checkout and is not
   installed. Promotion to shipped would add the separate executable to
   installed homes.
