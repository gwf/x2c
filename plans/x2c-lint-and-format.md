# x2c lint, format, and compiler-backed source tools

> Status: active - Gary accepted all six decisions on 2026-09-24. Re-evaluated 2026-09-24 against `dev` at
> `29326dbd`; lint placement measured on `76cead06`. Phases 0 through 7
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
| `tools/repo-metrics.py` | 387 | kept in Python; see Progress |
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
2. Port `gen-api-reference` and `gen-module-catalog` to scripts over the
   projection. `repo-metrics.py` stays in Python; see Progress. Generated docs must be byte-identical.
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
`shadow`. The two native-module `meta` warnings in `src/macros.x` report
`native`, so no compiler warning reports the generic `warning` code.

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

**Decision, 2026-09-24: `repo-metrics` stays in Python.** Gary judged the
port a mistake: it made the Pages workflow build the compiler only to count
lines for the landing page. `tools/repo-metrics.py` is restored, every
caller runs it again, the Pages workflow no longer builds the compiler, and
the x2c script is deleted. Its six output modes matched the script byte for
byte on the same tree. Do not port it again.

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

**Phase 4, 2026-09-24.** `commands/lint/idioms.x` adds four candidate rules
that each propose a respelling, and `commands/lint/fix.x` adds `--fix`: it
translates the file with the command's own compiler before and after the
edits and writes only edits whose generated C and header are
byte-identical, all together or else one at a time. Lint grew by 356
lines, fixtures included; no compiler change. Census on `src/` and `lib/`
(94 units), and what the proof kept on the 88 units outside the files
another session had reserved (`compiler`, `expressions`, `statements`,
`parse`, `literals`, `macros`):

| Rule | Found | Proposed | Proven | Rejected because |
| --- | --- | --- | --- | --- |
| `contains-in` | 87 | 58 | 43 | a C string literal as a `String` needle converts differently (13); a `position++` argument and an interpolated key (2) |
| `expression-body` | 5 | 4 | 1 | two compound-literal constructors in `lib/func.x` and `lisp_truth` emit different C |
| `member-arrow` | 7 | 7 | 0 | `struct dirent` from a system header (6); `iter->next`, a function-pointer field that is also a method (1) |
| `plain-string` | 7 | 7 | 0 | `%""` in quoted forms and a ternary branch, where the destination does not promote |

The cleanup commits are `write membership tests with in` (43 sites in 11
units) and `write a one-value body with =>` (1). Four rules from the
inventory produce no identical translation and were not added: a negated
membership test, because `!(x in c)` emits parentheses `!c.contains(x)`
does not; `negated-is` as a fix, for the same reason; grouped declarations
of one type, because the C keeps the source's grouping (a type-restarting
row is identical, which would group only unlike types); and `$auto`, which
emits `T_cleanup` where the hand-written `defer` named `free` or `close`.
`Type.method(x)` needs the callee's signature, which the token stream does
not carry, and was left for a rule over the parse. Over the 94 units the
report takes 6.9 s for all rules; `--fix` for one rule takes 20-31 s,
mostly the one-at-a-time retries in files with a rejected edit.

**Phase 5, 2026-09-24.** `commands/lint/comments.x` (283 lines) adds 13
comment rules, and `comment_slop.py` with its test and the
`find-comment-slop` skill are deleted (767 lines of Python); its ranking and
judging guidance moved into `clean-x2c-source`, which ranks files by counting
findings. A comment is a comment token, or a run of `//` tokens on
consecutive lines. The old tool's "vague or persuasive prose" became two
more `prohibited-prose` phrases, `important` and `obvious`. Parity on `src/`
and `lib/`, as file, first line, and category: all 112 old findings are
reported, and nothing else: history 6, `/**` on a static helper 1, module
header inventory 32, repeated prose 33, restated statement 2, restated name
27, section label 1, and the 10 vague-prose comments inside `prohibited-prose`
findings. One difference is deliberate: the old tool flagged every `/**` in
`src/` as a misplaced generated-reference delimiter (595 findings), which
`docs/AGENTS.md` now requires on public compiler callables, so the rule was
not carried over. The fixtures agree with the old tool too. Over the 94
units the old tool took 0.6 s and `x2c lint --all` takes 5.5 s, because it
also parses every unit. Phase 4's `--fix` read the include directories after
they were freed, which crashed about one run in thirty; it now reads the
request's copy.

**Reference parameters, 2026-09-24.** Added between Phases 5 and 6 at
Gary's request: `reference-parameter`, a style candidate in
`commands/lint/declarations.x` (66 lines), reports a `T *p` parameter of a
static function when the typed AST shows every use of `p` is `*p` or
`p->field` and every call passes `&v` for a caller's plain local. It has no
fix: the respelling changes generated C and callers.

**Phase 6, 2026-09-24.** `commands/lint/validation.x` (447 lines) and
`commands/lint/structure.x` (361 lines) add 20 rules over the functions the
compiler's definition rows give, in brace-syntax units, and
`agents/skills/find-x2c-overengineering/scripts/overengineering` (483 lines)
replaces the Python queue. Deleted: `audit-source-bloat.py`,
`redundant_validation.py` and `overengineering.py` with their tests, and all
of `x2c_source.py` except `mask_non_code`, which `tools/repo-metrics.py`
imports (3,238 lines of Python). Parity on `src/` and `lib/` (and
`*.xmacro`, which the validation analyzer read), as file, line, and rule:

| Rule | Old | New | Both | Differences |
| --- | --- | --- | --- | --- |
| return after `report_error` | 21 | 21 | 21 | - |
| shape-check diagnostics | 43 | 43 | 43 | - |
| validator diagnostics | 4 | 4 | 4 | - |
| recursive validator | 19 | 14 | 14 | 5 compile-time `meta` functions in `autodiff.xmacro`, which have no definition rows |
| validation framework | 4 | 4 | 4 | - |
| static match capture | 1 | 1 | 1 | - |
| silent shape guard | 336 | 367 | 334 | 2 in `autodiff.xmacro` meta functions; 33 new in `lib/lisp.x` functions the regex never found |
| return after raise | 0 | 1 | 0 | the old reader looked for `<cause>` and found no shared causes; the rule now reads the atoms and skips a raise that is a braceless body |
| struct copy | 188 | 188 | 185 | 3 are the first function of a file, which the regex started after the includes |
| manual bookkeeping | 9 | 9 | 9 | - |
| lifecycle pair | 2 | 2 | 2 | - |
| enum, table, and switch | 1 | 1 | 1 | - |
| internal type | 107 | 106 | 106 | `ErrorCatchSite`, which `src/emit.x` spells inside a quoted form |
| duplicate body | 8 | 8 | 8 | - |
| repeated routes | 53 | 62 | 50 | the regex read hyphenated atoms in quoted forms as calls (`void-op (` as `op`); 9 groups gain or lose members |

Not carried over: the bloat audit's merged areas, scores, stable IDs, JSON,
and `--compare`; its ordinal-switch detector (no current findings) and its
cosmetic counts, which the width, blank-line, ruler, and stock-prose rules
report; and the validation analyzer's scores, producer grouping, JSON,
`--rev`, and `--compare`. A historical tree is now checked from a worktree
of that revision. The overengineering script keeps the inventory, history,
selection, and run record; `trace-deletion` output matched the old script on
`79417aab` (32 lines, 28 ranges). Its structure signal now comes from lint
findings, so of the old run's five selections one (`_import`) is still
selected, and 3,886 of 3,959 shared regions have the same term, bookkeeping,
and size signals; 17 regions the regex invented from macro text and one
`static struct` variable are gone. Old tools: validation 5-7 s, bloat audit
15-26 s of processor time, overengineering 66 s; `x2c lint --all` over the
same units takes 11-16 s and the overengineering scan 14 s. Findings and
function rows are promoted out of the parse's pool, and the proven
`contains-in` fixes were applied to the linter itself.

**Phase 7, 2026-09-24.** The editor lint kind was not built: decision 6
keeps lint experimental and uninstalled, and the phase makes it conditional
on shipping lint to users. `x2c lint --fmt-check` (with `--fmt-diff` to
print the difference) reports files whose spacing would change and never
writes; `commands/lint/format.x` is 88 lines. Formatting changes only space:
trailing space (also inside comments), more than one blank line in a row,
the final newline, space before `,` or `;`, and a missing space after `,` or
between a control keyword and `(`, outside quoted forms. It keeps
indentation, and a file whose reformatted text does not scan to the same
tokens, comments compared without trailing space, is reported and left
alone. Measured over all 1,361 tracked `.x` units outside `bootstrap/`: 139
files and 571 lines would change (unittest 380, commands 72, packages 62,
examples 45, src 8, etc 2, lib 2); one fixture, `indent-tab.x`, is refused
because its tab indentation is syntax. The check takes 1.4 s for all of them.

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
