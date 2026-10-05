# x2c code standard: consolidation and adoption

> Status: active - needs Gary's review of the standard and decisions D1-D5.
> [agents/x2c-code-standard.md](../agents/x2c-code-standard.md) was written
> on 2026-10-04 against `dev` at `4107b60a`. It is the proposed consolidated
> definition. The older guides and skills still hold their own copies of
> the rules until phase 1 reduces them to links and examples.

## The result

One document defines what good x2c source is, at every level from a
statement to the compiler pipeline. It also gives the signal that finds each
violation and the procedure that repairs it. Guides, skills, `x2c lint`, and
reviews cite its rule IDs. When the style changes, the standard changes
first and the tools follow.

## How the standard was built

Six read-only extractions inventoried every prescriptive statement:

| Source | Rules found |
| --- | --- |
| `agents/` guides: philosophy, organization, adapters, lowering, AST patterns, diagnostics, root `AGENTS.md` | 182 |
| skills: beautify, clean, simplify, validation, overengineering, review, plan, fix | 81 rules, 9 procedures |
| the book's guide chapters and the language tour | 310 rules, 10 decision tables |
| architecture docs and macro, meta, and Lisp plans | 90 |
| `x2c lint`, `x2c graph`, and tool scripts | 68 lint codes, 93 checks |
| git history from 2026-09-17 to 2026-10-04 | 27 transformation patterns, 12 lessons |

The source style guide was read in full. The standard merges duplicates,
settles the conflicts listed below, adds the rules that history applied
but no guide stated, and keeps each rule to one or two sentences.

## Conflicts the standard settles

These follow from current source, a probe, or the more recent of two guides.
None changes public behavior.

| Conflict | Settled as | Evidence |
| --- | --- | --- |
| Name length: guide 25, lint 30 | 25 (NM-3); lint moves to 25 | the guide is the stated band; lint is advisory |
| Bare `{}` at a `Var` destination: guide says Null | fresh Map; `[]` fresh Array (EX-1) | probe on `builds/0/x2c`: `map=1 arr=1` |
| Hand `cdr` walk versus `foreach` | `foreach` (ST-12) | iteration chapter; List `foreach` is the fast path since 2026-09-17 |
| `%()` versus quotation for returned syntax | quotation for C code, `%()` for data and internal nodes (MA-5, MA-6) | lowering guide and quotation adoption |
| Raw `%()` patterns versus grammar forms | grammar form when one exists (MA-7) | dual-macro contract E45 |
| Lowering rule 2: every loop in a slot function | a choice (MA-8) | metalanguage plan M4 |
| Record copied into locals | back to parameters (FA-3) | source organization record rule |
| "Delete uncalled functions" versus public API | private only; public needs authorization (FI-7, PR-10) | overengineering skills |
| 3x3 repetition rule versus abbreviation macros | the owner must hold a fact (FA-5) | simplify removal patterns |
| `$auto`/`$let` change error-exit behavior in a neutral rewrite | allowed and reported as a neutral tweak (proof table) | beautification waves |
| Chained sub-dispatchers | forbidden (FN-4) | `b57c8cef` (+53/-119) |
| Hot-path limits existed only in skills and commit messages | HP-1 to HP-5 | Wave 3 corrections `ff7f1b0a`, `e6a36a7e`, `c36a652d`, `24727927` |
| Short structured raises versus report catalogues | short raises stay inline (DG-1) | diagnostics guide |

## Decisions for Gary

**D1. Make the standard the single definition.** Recommended. Phase 1
reduces the style guide to worked examples keyed by rule ID and removes the
rule text from the organization guide and the skills. The standard grows
only through its own review.

**D2. One detail vocabulary for runtime Errors.** Two facts each have two
keys today. The public operation as `"Type.method"` is `owner` in 116
`lib/` raises and `operation` in 87; the book teaches `operation`. A short
reason is `why` in 26 `lib/` raises and `reason` in 3, while packages use
`reason` in 180 and `why` in none. A catch that reads details sees the key,
so a change is observable. Recommended: `operation` and `reason` everywhere
(DG-7), as one mechanical change with its tests.

**D3. Cause for malformed external text.** The book says `<malformed>`;
`lib/json.x` and `lib/regex.x` raise `<bad-arg>` for text that is not JSON
or not a pattern, while the yyjson package raises `<malformed>`. Moving
between them changes which catch fires. Recommended: `<malformed>` in both
runtime modules (ER-2).

**D4. A lint ratchet in the gate.** The whole-tree lint run takes 4 seconds
over `src/` and `lib/`. A ratchet would fail publication when a
`violation` count rises above a checked-in baseline. The process ceiling in
`AGENTS.md` requires Gary's approval and an offsetting removal. The proposed
offset is the lint-fixture portion of `commands-check`, but a
whole-tree count does not establish detector or fixer correctness. Equivalent
coverage and comparable cost still need evidence before that replacement
can be approved. Recommended only after phase 2 adds suppressions.

**D5. Non-static `builtin_*` slot functions.** NM-6 limits non-static names
to the C interface. The lowering slot functions in `src/builtins.x` are
non-static because templates call them by name. Recommended: record them
as a named exception in NM-6 after checking whether `static` breaks the
template calls.

## Phase 1: one definition

1. Rewrite `agents/x2c-coding-style-guide.md` as the examples companion:
   keep each prefer/avoid pair under the rule ID it illustrates, and delete
   the rule prose that the standard now owns.
2. Reduce `agents/x2c-code-organization-guide.md` to the compiler and
   runtime module maps, updated for the current files (it omits
   `operator-ledger.x`, the `*-reports.xmacro` catalogues, and the typed
   collection, path, and process modules).
3. Replace the style passages in the skills with rule-ID references. The
   largest are `simplify-x2c-source/references/removal-patterns.md`,
   beautify steps 1-6, clean's lint and comment lists, and
   find-redundant-validation's stage-trust and keep-check rules. Each skill
   keeps its procedure, scope, and proof obligation.
4. Fix the stale claims the extractions found, in place:
   - `agents/lowering-with-macros.md` examples use `_lower_try(Walk walk,
     ...)`; current code is `Walk._lower_try(Walk &w, ...)`.
   - `agents/adapters-macros-decorators.md` cites `$match.lease`, twelve
     `StateRef` aliases in `lib/iter.x` (only `UnzipColumnRef` and
     `UnzipSharedRef` remain), `x2c.ident` in
     `lib/map-generics.xmacro` (none), and line ranges in `logger.x`,
     `common.x`, and `varops.x` that moved.
   - `agents/logger-and-diagnostics-guide.md` says Diagnostics stores
     entries newest-first; `src/diagnostics.x` stores them in order.
   - `agents/x2c-philosophy.md` places `_is_reserved_spelling` in
     `compiler.x` (it is in `symbols.x`) and describes Pool over a Map (it
     uses `PoolTable`).
   - `docs/src/internals/implementation-map.md` and `architecture.md` say
     `transform.x` owns lambdas and cleanup; `callables.x` and `cleanup.x`
     do.
   - `plans/macro-sdk-and-system-macros.md` and `plans/meta-followups.md`
     cite deleted Lisp files and `src/comptime.x`.
5. Fix the book samples that teach against the standard (TE-5):
   `exceptions.md` returns after a raise; `wrapping-c-libraries.md` builds
   with `cons` and reverses; the tour and `library/overview.md` use
   explicit converters, `getdefault(...).integer() + 1`, and a bare
   `Scope.retain`/`release` pair; `iteration.md` indexes an Array after
   recommending `foreach`; several chapters define unqualified shared
   macros; `match.md` shows the C spelling `Var_is`.

Validation: `tools/gate-state.py ensure doc-check`. Phase 1 changes no code.

## Phase 2: lint follows the standard

1. Print each lint code's standard rule ID in `x2c lint --rules` and in
   findings, from one table in `commands/lint/lint.x`.
2. Move `long-name` to 25 characters. Fix the `reference-parameter`
   section reference to a real rule.
3. Add fixture lines for the ten codes that have none:
   `fresh-literal-null-guard`, `growth-check`, `manual-shape-checks`,
   `validator-shape`, `recursive-validator`, `validation-framework`,
   `static-match-capture`, `enum-table-switch`, `duplicate-function-body`,
   `doc-comment-tier`.
4. Add a suppression comment that cites a rule ID and a reason. Phase 3
   and D4 need it.
5. Add detectors for the signals marked "none" in the standard, cheapest
   and most frequent first. Current counts at `4107b60a` over `src/`,
   `lib/`, and `commands/`:

   | Signal | Rule | Count | Detector |
   | --- | --- | ---: | --- |
   | `x2c_expr_*` or `x2c_literal_*` builder calls | MA-5 | 65 | token |
   | `old_`, `saved_`, `previous_` locals | NM-4 | 38 | token |
   | `.reverse()` after `cons` accumulation | EX-10 | up to 38 | AST |
   | `$(x2c.ident` | LI-2 | 17 | token |
   | `} else` | ST-1 | 13 | token |
   | `report_error(` with literal wording | DG-1 | 10 | token |
   | `$(defun` | LI-1 | 4 | token |
   | `String.new("")`, `Array.new()`, `Map.new()` | EX-1 | 4 | token |
   | assignment in a condition | ST-4 | 1 | token |
   | file over 1,500 lines | FI-1 | 7 files | metric |
   | section over 400 lines; dispatcher arm over 3 lines | FI-5, FN-3 | not counted | token and metric |
   | uncalled static function; one-use wrapper | FI-7, FN-2 | not counted | graph |
   | `Type.method(x)` where `x.method()` fits | EX-5 | not counted | typed AST |
   | `Var` local with one static type | VT-1 | not counted | typed AST |

   Some counts include legitimate uses; for example `x2c_expr_*` is the
   public builder API in `lib/meta.x`. Each detector starts as a
   `candidate`.

Validation: `make commands` and the lint fixtures through `commands-check`.

## Phase 3: apply the standard to the tree

The census below is the starting baseline: `x2c lint --all` over every
hand-authored `src/*.x` and `lib/*.x` at `4107b60a`, 1,498 findings.

| Code | Kind | Count |
| --- | --- | ---: |
| `silent-shape-guard` | candidate | 341 |
| `short-control-flow` | candidate | 241 |
| `internal-type` | candidate | 180 |
| `runtime-forward-declaration` | candidate | 161 |
| `struct-copy` | candidate | 121 |
| `repeated-routes` | candidate | 53 |
| `horizontal-form` | candidate | 51 |
| `wrapped-opening-line` | violation | 41 |
| `repeated-accessor` | candidate | 38 |
| `prohibited-prose` | candidate | 31 |
| `repeated-prose` | candidate | 23 |
| `long-name` | candidate | 22 |
| `module-header-inventory` | candidate | 21 |
| `shape-diagnostics` | candidate | 19 |
| `long-function` | candidate | 17 |
| `restates-name`, `one-statement-braces` | violation | 16 each |
| `contains-in` | candidate | 15 |
| `deep-nesting` | candidate | 11 |
| `long-parameter-list`, `src-forward-declaration` | mixed | 9 each |
| `over-width` | violation | 8 |
| 17 other codes | mixed | 54 |

The 106 violations are mechanical and go first, as respellings with
byte-identical generated C. Candidates go through the procedures in the
standard, one connected slice at a time. Shape drift since the
beautification campaign also returns here: `src/` functions over 40 lines
rose from 6 at `0bccd679` to 12 (`x2c lint --rule long-function`,
excluding generated `src/linked-meta.x`), and `src/macros.x` grew from 3,851 to
4,605 lines after its split.

Three packages (`libcurl`, `blis`, `termbox2`) define `$report.<pkg>.<case>`
macros that raise runtime Errors, and `libuv` keeps them in an unprefixed
`errors.xmacro`. DG-1 asks for one `$error.<area>.<condition>` macro per
condition in `<unit>-errors.xmacro`; those packages migrate with phase 3.

Validation per slice follows the standard's proof table; publication
follows `AGENTS.md`.

## Phase 4: skills cite the standard

Each source-quality skill keeps its task boundary, procedure, and proof, and
cites rule IDs for what good code is. A rule change then edits one file.
Skills affected: beautify, clean, simplify, find-redundant-validation,
find-x2c-overengineering, investigate-x2c-overengineering, review, plan,
and fix.

## Plan review

- Established facts: the standard restates contracts their owners already
  enforce, such as shared causes never returning, producer shape
  guarantees, and the region analysis. It adds no consumer check.
- Reuse and deletion: phase 1 deletes duplicate rule text from about ten
  files. Phase 2 extends the existing lint engine and graph. No new tool,
  gate, or representation is proposed except the D4 ratchet, which needs
  Gary's approval and a verified comparable-cost offset.
- Idiom: the rules describe x2c as written on `dev` after the 2026-09
  campaigns, including the corrections those campaigns made.
- Validators, diagnostics, negative fixtures: none proposed. The lint
  detectors in phase 2 are advisory candidates until D4.
