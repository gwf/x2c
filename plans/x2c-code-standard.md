# x2c code standard: authority, enforcement, and improvement

> Status: active - Gary accepted the standard and decisions D1-D5 on
> 2026-10-05. Execution starts at stage 1 from `origin/dev`; stages 1 and 2
> are independent and may run in parallel. Record each landed stage in
> [Progress](#progress). The standard is
> [agents/x2c-code-standard.md](../agents/x2c-code-standard.md).

## The result

[agents/x2c-code-standard.md](../agents/x2c-code-standard.md) is the single
definition of good x2c source. Every other guide, skill, and tool cites its
rule IDs and holds no competing copy of a rule. `x2c lint` reports each
finding under its rule ID, a ratchet keeps violation counts from rising, and
repeated scan-and-fix cycles lower them. When a cycle shows a rule is wrong
or missing, the standard changes first, then the detector, then the code.

## Rules for whoever executes this plan

These hold in every stage. They come from the root `AGENTS.md`, the
standard, and this plan's decisions.

1. Read the root `AGENTS.md`, `agents/README.md`, the standard, and this
   plan before editing. Use the task skill each stage names.
2. Start each stage from current `origin/dev`. Fetch and integrate
   `origin/dev` again before publication.
3. Move rule text without changing its meaning. If moving a rule exposes
   a contradiction with current source, the standard, or the book, stop
   that item and record it under [Open questions](#open-questions) for
   Gary; continue the other items.
4. The standard is the only place rule text may change. A guide, skill, or
   tool that disagrees with it is updated to match it, unless step 3
   applies.
5. Change public behavior only where D2 and D3 authorize it. Any other
   observable change is a defect in the work.
6. Never rebaseline a stage diff, fixture expectation, or lint baseline to
   make a change pass, except where a step below names the rebaseline and
   its review.
7. Keep new files ASCII and every hand-authored line within 79 columns.
   Write prose to rule CM-8 of the standard.
8. Validate and deliver as the root `AGENTS.md` states: documentation-only
   work runs `tools/gate-state.py ensure doc-check`; code, tool, and test
   work runs `tools/gate-state.py ensure agent-pr-check`. Use the delivery
   mode Gary set for the session; when he set none, it is direct delivery
   to `dev` with `git push origin HEAD:refs/heads/dev`.
9. A failed required check stops that stage's publication. Keep the log in
   `debug/`, isolate the cause with focused checks, and report the failing
   command.
10. After each stage lands, update [Progress](#progress) with the commit,
    the date, and any measured result, in the same delivery or the next.

## Accepted decisions

**D1. The standard is the single definition.** The style guide becomes the
worked examples for the standard's rule IDs. The organization guide keeps
only the module maps. Skills and `AGENTS.md` files cite rule IDs.

**D2. One detail vocabulary for runtime Errors.** The public operation as
`"Type.method"` uses the key `operation`, and a short lower-case reason
uses `reason`. At `4107b60a`, `lib/` writes `owner` in 118 raises and
`why` in 26; both become the accepted keys. Packages already use `reason`.

**D3. Malformed external text raises `<malformed>`.** `lib/json.x` and
`lib/regex.x` move from `<bad-arg>` to `<malformed>` for text that is not
JSON and for a pattern that does not parse. A bad argument that is not
external text, such as a missing file path, keeps its current cause.

**D4. A lint ratchet guards violation counts.** The publication path fails
when any `violation` count over `src/` and `lib/` rises above a checked-in
baseline. Candidates are not counted. Gary approved the ratchet on
2026-10-05. It runs inside the existing lint smoke test in
`commands-check`, so no new gate target is added; stage 3 records its
measured time.

**D5. `builtin_*` linkage is decided by evidence.** If the slot functions
in `src/builtins.x` compile and pass with `static`, make them `static`.
Otherwise add them to NM-6 as a named exception with the reason.

## Conflicts the standard settles

These follow from current source, a probe, or the more recent of two
guides. None changes public behavior.

| Conflict | Settled as | Evidence |
| --- | --- | --- |
| Name length: guide 25, lint 30 | 25 (NM-3); lint moves to 25 | the guide is the stated band; lint is advisory |
| Bare `{}` at a `Var` destination: guide says Null | fresh Map; `[]` fresh Array (EX-1) | probe on `builds/0/x2c`: `map=1 arr=1` |
| Hand `cdr` walk versus `foreach` | `foreach` (ST-12) | iteration chapter |
| `%()` versus quotation for returned syntax | quotation for C code, `%()` for data and internal nodes (MA-5, MA-6) | lowering guide and quotation adoption |
| Raw `%()` patterns versus grammar forms | grammar form when one exists (MA-7) | dual-macro contract E45 |
| Lowering rule 2: every loop in a slot function | a choice (MA-8) | metalanguage plan M4 |
| Record copied into locals | back to parameters (FA-3) | source organization record rule |
| "Delete uncalled functions" versus public API | private only (FI-7, PR-10) | overengineering skills |
| 3x3 repetition rule versus abbreviation macros | the owner must hold a fact (FA-5) | simplify removal patterns |
| `$auto`/`$let` change error exits in a neutral rewrite | allowed and reported (proof table) | beautification waves |
| Chained sub-dispatchers | forbidden (FN-4) | `b57c8cef` (+53/-119) |
| Hot-path limits existed only in skills and commits | HP-1 to HP-5 | `ff7f1b0a`, `e6a36a7e`, `c36a652d`, `24727927` |
| Short structured raises versus report catalogues | short raises stay inline (DG-1) | diagnostics guide |

## Stage 1: make the standard the authority

Documentation only. Skill: `execute-x2c-plan`. One delivery; split it in
two (agent documents, then the book) only if review of one diff becomes
hard. Gate: `doc-check`.

1. In `agents/x2c-code-standard.md`, replace the draft status paragraph
   with: the standard is accepted as of 2026-10-05, it is the single
   definition of x2c source style, and this plan tracks its adoption. In
   DG-7, delete the sentence about open decision D2. In "How to read this
   standard", replace the sentence saying the style guide holds examples
   "until the adoption plan folds them in" with one saying the style guide
   holds the worked examples, filed under rule IDs.
2. Root `AGENTS.md`: replace the bullet "Follow
   `agents/x2c-coding-style-guide.md`: 2-space indentation, ..." with a
   bullet that says to follow `agents/x2c-code-standard.md`, the single
   definition of x2c source style, and to update the book when documented
   behavior changes. Leave every other root rule unchanged.
3. `src/AGENTS.md` and `lib/AGENTS.md`: add one line that cites the
   standard. `docs/AGENTS.md`: change the sentence naming
   `agents/x2c-coding-style-guide.md` as the writing standard for doc
   comments so it names CM-5 in the standard.
4. `agents/README.md`: list the standard first under "Open references when
   relevant" as the authority, drop "a draft under review", and describe
   the style guide as its worked examples and the organization guide as the
   module maps. `agents/x2c-development-guide.md` (lines near 113) and
   `agents/x2c-philosophy.md` (line near 964): point to the standard.
5. Rewrite `agents/x2c-coding-style-guide.md` as "x2c Source Style
   Examples":
   - Keep every prefer/avoid example pair. File each under a heading that
     names its rule ID and one-line rule, in the standard's order.
   - Delete the rule prose the standard now holds. Keep short explanations
     that make an example readable.
   - Keep the existing heading anchors that other files link to, or update
     each linking file in the same delivery. Find them with
     `git grep -n 'x2c-coding-style-guide.md#'`.
   - A rule in the old guide with no counterpart in the standard is an
     open question for Gary (rule 3), not a deletion.
6. Reduce `agents/x2c-code-organization-guide.md` to the compiler module
   map and the runtime module map, updated for the current files. Add the
   files the maps omit: `src/operator-ledger.x`, `src/*-reports.xmacro`,
   `src/grammar.xmacro`, `src/fields.xmacro`, and the runtime modules for
   typed collections, `path`, `process`, `var-ledger`, `lisp-targets`,
   `lisp-init`, and `meta`. Move its rules to citations of MO, FI, AR, and
   RT rule IDs. Keep it in the `tools/check-docs` path audit.
7. Add `agents/x2c-code-standard.md` to `_path_audit` in `tools/check-docs`
   so its cited paths and lines are checked.
8. Skills. In each listed `SKILL.md` and its `references/`, replace text
   that defines style with citations of rule IDs. Each skill keeps its
   trigger, scope, procedure, proof obligation, and report format.
   - `beautify-x2c-source`: rewrite steps 1-6 to cite PR-3, FA-5 to FA-8,
     MO-3, FN-1 to FN-6, FA-2, FA-3, LT-1, NM, FI-4, FI-5, and CM. Fix the
     proof statement: `make stage-1 && make stage-diff-1` proves the
     compiler's output is unchanged; `make stage-diff-0` against a current
     bootstrap proves a respelling's own generated C is unchanged.
   - `clean-x2c-source`: replace the lint lists and comment rules with
     citations of LY, ST, EX, CM, and NM and a pointer to
     `x2c lint --rules`.
   - `simplify-x2c-source`: keep `references/removal-patterns.md` as
     calibration evidence and examples, and make each pattern cite its rule
     (PR-2, PR-3, FA-3, FA-5, FA-7, FA-8, FA-9, MA-2).
   - `find-redundant-validation`: cite PR-4, ER-4, ER-5, FA-9, and the
     standard's trust-boundary paragraph; keep `references/calibration.md`.
   - `find-x2c-overengineering`, `investigate-x2c-overengineering`,
     `review-x2c-repo`, `plan-x2c-change`, `fix-x2c-bug`: cite PR-2, PR-3,
     PR-4, PR-10, FA-7, and TE-2 where they now restate those rules.
9. Fix the stale claims the inventory found:
   - `agents/lowering-with-macros.md`: examples use
     `_lower_try(Walk walk, ...)`; current code is
     `Walk._lower_try(Walk &w, ...)` in `src/cleanup.x`. Rule 2 (every loop
     in a slot function) becomes a choice, per MA-8.
   - `agents/adapters-macros-decorators.md`: `$match.lease` is now
     `$match.plan` (`lib/match-cache.x`); `lib/iter.x` keeps only
     `UnzipColumnRef` and `UnzipSharedRef`; `lib/map-generics.xmacro`
     calls `Scope_malloc` and friends directly, without `x2c.ident`;
     re-cite the moved line ranges in `lib/logger.x`, `lib/common.x`, and
     `lib/varops.x`.
   - `agents/logger-and-diagnostics-guide.md`: Diagnostics stores entries
     in chronological order (`src/diagnostics.x`).
   - `agents/x2c-philosophy.md`: `_is_reserved_spelling` is in
     `src/symbols.x`; Pool uses a private `PoolTable`, not a Map.
   - `docs/src/internals/implementation-map.md` and
     `docs/src/internals/architecture.md`: `src/callables.x` owns lambda
     and adapter synthesis and `src/cleanup.x` owns cleanup placement.
   - `plans/macro-sdk-and-system-macros.md` and `plans/meta-followups.md`:
     mark the citations of deleted files (`etc/builtin-macros.xlisp`,
     `lib/varops.xlisp`, `lib/system-macros.xlisp`, `src/comptime.x`,
     `etc/comptime.xlisp`) as removed.
10. Fix the book samples that teach against the standard (TE-5). Each
    change keeps the sample's printed output; `make doc-examples` and
    `make doc-outputs` prove it.
    - `docs/src/guide/exceptions.md`: delete the `return;` after
      `raise %(bad-arg ...)` (ER-4).
    - `docs/src/guide/wrapping-c-libraries.md` (`Feed.titles`): build with
      an Array and `list_free()` (EX-10).
    - `examples/tours/language.x`, `docs/src/library/overview.md`,
      `docs/src/guide/exceptions.md`, `docs/src/guide/scripting.md`: drop
      converters at converting destinations (EX-4); use
      `counts[word] += 1` (ST-11) and `words()` where the tour splits on
      spaces; replace a bare `Scope.retain`/`Scope.release` pair with
      `$scope()` and a manual `free` with `$auto` (LT-1).
    - `docs/src/guide/iteration.md`: correct the sentence that says the
      first program brackets work with `Scope.retain`; use `foreach` in
      place of the index loop that follows the `foreach` advice.
    - `docs/src/guide/idioms.md`, `docs/src/guide/meta-functions.md`,
      `docs/src/guide/from-c.md`: qualify shared macro names (MA-4).
    - `docs/src/guide/match.md`: write `value is <list>` in place of
      `Var_is(v, <list>)` (ST-5).
    The tour is an executable example: also run its check from
    `examples/manifest.txt`. Examples belong to Gary's release work; if
    a manifest check fails for a reason this change did not cause, record
    it and continue. Because the tour is code, this delivery's gate is
    `agent-pr-check`; or deliver the tour separately and keep the rest on
    `doc-check`.
11. Update `plans/README.md`: this plan's entry says stage 1 landed.

Done when: `git grep -n 'x2c-coding-style-guide.md'` finds only links to
the examples document; no skill restates a rule the standard holds;
`doc-check`, `make doc-examples`, and `make doc-outputs` pass.

## Stage 2: the accepted behavior changes

Code. Skill: `execute-x2c-plan`. Three independent deliveries. Gate:
`agent-pr-check` for each, or once for all three if they land together.

### D2: detail keys

1. List every raise that writes the old keys:
   `git grep -nE '\((owner|why) ' -- lib src commands packages`. Rename
   `owner` to `operation` and `why` to `reason` in each raise and in each
   `*-errors.xmacro` macro body.
2. List every reader of those keys and update it: catch patterns, `assoc`
   or `getindex` on Error details, tests, compiler fixture expectations,
   book text and samples, examples, package code and tests, and the REPL.
   Search for `owner` and `why` next to `catch`, `details`, `assoc`, `%(`,
   and in `unittest/compiler-fixtures/*.stdout`,
   `unittest/compiler-fixtures/*.stderr`, `docs/src/**/*.md`,
   `examples/**`, `commands/**`, and `packages/**`. A word "owner" that is
   not an Error detail key stays.
3. Update the `Raises:` paragraphs of every `/**` comment that names the
   old keys, and run `make doc-generate`.
4. Proof: `make verify`, `make -C unittest cli-probes`, `make
   doc-examples`, `make doc-outputs`, and `make commands-check`; the gate.
   Package tests run through `make packages-check` when the dependency
   cache is prepared; otherwise record that they were not run.

### D3: `<malformed>` for external text

1. In `lib/json-errors.xmacro` and `lib/regex-errors.xmacro`, change the
   cause of the macros that report text that is not JSON and a pattern that
   does not parse from `bad-arg` to `malformed`. Keep the cause of
   argument errors that are not about the text, such as the
   `Json.read_file` path case.
2. Update their `/**` `Raises:` text in `lib/json.x` and `lib/regex.x`, the
   book (`docs/src/guide/scripting.md` describes both), and every test,
   fixture, example, and catch that selects `<bad-arg>` for these cases.
3. Proof: the same commands as D2.

### D5: `builtin_*` linkage

1. Make the non-static `builtin_*` functions in `src/builtins.x` `static`
   in a local branch and run `make build`, `make stage-1`, and the
   compiler fixtures.
2. If everything passes, keep the change and deliver it with the gate.
3. If a template or `x2c.ident` lookup needs external linkage, revert it
   and add to NM-6 in the standard: "The lowering slot functions
   `builtin_*` in `src/builtins.x` stay non-static because <the measured
   reason>." That edit is documentation only.

## Stage 3: lint enforces the standard

Code under `commands/lint/`. Skill: `execute-x2c-plan`. Start after stage 1
lands, because rule IDs must be final. Deliver in the order below; each
item is one delivery with `agent-pr-check`.

1. **Rule IDs.** In `commands/lint/lint.x`, the `Rule.section` field names a
   style-guide section. Rename the field `rule` and set it to the
   standard's rule ID for every code, taken from the standard's
   [signal catalog](../agents/x2c-code-standard.md#finding-bad-code). Print
   it in each finding and in `--rules`. Update the doc comment of `Rule`.
   Update `commands/lint/tests/expected.txt` and
   `tests/validation-macros.expected` for the new output, and review every
   changed line.
2. **Thresholds.** Set `long-name` to 25 characters, measured without the
   owner, in `commands/lint/structure.x`. Update the fixture.
3. **Fixtures.** Add a fixture line for each code that has none:
   `fresh-literal-null-guard`, `growth-check`, `manual-shape-checks`,
   `validator-shape`, `recursive-validator`, `validation-framework`,
   `static-match-capture`, `enum-table-switch`,
   `duplicate-function-body`, `doc-comment-tier`. Use a minimal positive
   case in `commands/lint/tests/src/` and record the expected finding.
4. **Suppression.** Accept a comment on the line before a finding:
   `// lint: allow CODE RULE-ID: reason`. The finding is dropped only when
   the code matches, the rule ID matches that code's rule, and the reason
   is non-empty; otherwise lint reports a `bad-suppression` violation.
   Add fixtures for an accepted, a mismatched, and an empty suppression.
   Document the syntax in the standard's "Finding bad code" section.
5. **New detectors.** Add each as a `candidate`, with a fixture, in this
   order. The counts are from `4107b60a`.

   | Signal | Rule | Count | Kind |
   | --- | --- | ---: | --- |
   | `} else` on one line | ST-1 | 13 | token; `violation` once the count is 0 |
   | `String.new("")`, `Array.new()`, `Map.new()` | EX-1 | 4 | token |
   | `old_`, `saved_`, `previous_` locals | NM-4 | 38 | token |
   | `$(x2c.ident` | LI-2 | 17 | token |
   | `$(defun` in `src/` or `lib/` | LI-1 | 4 | token |
   | `report_error(` with a literal message outside report macros | DG-1 | 10 | token |
   | assignment in a condition outside a read loop | ST-4 | 1 | token |
   | file over 1,500 lines; section over 400 lines | FI-1, FI-5 | 7 files | metric |
   | dispatcher arm over 3 lines | FN-3 | not counted | token |
   | uncalled static function | FI-7 | not counted | graph |

   Builder calls (`x2c_expr_*`) and `Type.method(x)` receivers need
   typed-AST support; record them as later work in Progress.
6. **Ratchet (D4).**
   - Add `commands/lint/baseline.txt`: one line per `violation` code,
     `CODE COUNT`, from `x2c lint --all` over the hand-authored `src/*.x`
     and `lib/*.x` (excluding `lib/x2c.x` and generated
     `src/linked-meta.x`), sorted by code.
   - In `commands/lint/tests/run.sh`, after the fixture comparison, run
     that census and compare it with the baseline. Fail when a count is
     higher, naming the code, the baseline, and the current count. When a
     count is lower, pass and print the line to lower in the baseline.
   - Use `xargs -0` or a `while read` loop to pass the file list; zsh does
     not split an unquoted variable.
   - Measure `make commands-check` before and after with
     `/usr/bin/time -l` and record both wall times in Progress.

Done when: every finding prints a rule ID, the ten codes have fixtures,
suppression works and is documented, the ratchet runs in
`commands-check`, and Progress records the added time.

## Stage 4: scan-and-fix cycles

Code. Repeats after stage 3 lands. One connected slice per delivery;
deliver as stages 1-3 do.

1. **First cycle: violations.** Fix every `violation` that the census
   reports. These are respellings (`wrapped-opening-line`,
   `one-statement-braces`, `restates-name`, `over-width`,
   `src-forward-declaration`, `forward-declaration`,
   `subject-parameter-name`, `blank-line-stack`, and the comment rules);
   the census at `4107b60a` counted 106. Prove each file with
   `make stage-diff-0` against a current bootstrap; compiler sources also
   run `make stage-1 && make stage-diff-1`. Lower `baseline.txt` in the
   same delivery.
2. **Later cycles: candidates.** For each cycle:
   1. Run the census and rank files by findings.
   2. Choose one connected slice: one file for
      `beautify-x2c-source`, one connected mechanism across files for
      `simplify-x2c-source`, or one producer and its consumers for the
      `silent-shape-guard` findings with `find-redundant-validation`
      followed by `simplify-x2c-source`.
   3. Repair it in the standard's order: delete, reuse, reshape, adopt
      idioms, rename and reorder, comment pass.
   4. Prove it with the standard's proof table. A hot-path file also needs
      HP-1's paired measurement.
   5. Lower `baseline.txt` for any violation count that fell, and record
      the cycle in Progress: files, `.x` lines deleted and added, findings
      before and after.
3. **Feedback.** When a cycle shows a rule is wrong, missing, or too
   strict, stop that slice, record the evidence under Open questions, and
   change the standard only with Gary's agreement. Then update the
   detector, then the code.
4. Start the candidate cycles with the shape drift since the
   beautification campaign: `src/` functions over 40 lines (12 at
   `4107b60a`, excluding `src/linked-meta.x`) and `src/macros.x` (4,605
   lines; FI-1 review).

Three packages (`libcurl`, `blis`, `termbox2`) define `$report.<pkg>.<case>`
macros that raise runtime Errors, and `libuv` keeps its macros in an
unprefixed `errors.xmacro`. DG-1 asks for one `$error.<area>.<condition>`
macro per condition in `<unit>-errors.xmacro`. Migrate them in a stage 4
cycle with `make packages-check`.

## Baseline census

`x2c lint --all` over every hand-authored `src/*.x` and `lib/*.x` at
`4107b60a`: 1,498 findings, 106 of them violations.

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

Command, from the repository root after `make commands`:

```sh
git ls-files 'src/*.x' 'lib/*.x' | grep -v -e '^lib/x2c.x$' \
  -e '^src/linked-meta.x$' | tr '\n' '\0' |
  xargs -0 builds/0/libexec/x2c-lint --all -I src -I lib
```

## How the standard was built

Six read-only extractions inventoried every prescriptive statement: 182
rules from the `agents/` guides and root `AGENTS.md`, 81 rules and 9
procedures from the skills, 310 rules and 10 decision tables from the book,
90 architectural rules from the internals docs and plans, 68 lint codes and
93 checks from the tools, and 27 transformation patterns and 12 lessons
from the history of 2026-09-17 to 2026-10-04. Three fact-check passes
against current source and probes followed.

## Open questions

### Stage 1: simplification calibration adds a stronger stopping rule

PR-3 requires deletion before rearranging. The calibration reference
`agents/skills/simplify-x2c-source/references/removal-patterns.md` also says
"do not run final gates until a second architectural pass is empty".
The standard's repair procedure and root process ceiling contain no such
empty-pass prerequisite. That sentence remains unchanged pending Gary's
choice. Options: retain it as historical calibration, retire it, or add an
explicit bounded review requirement to the standard. Other stage 1 work
continues.

### Stage 2 D2: Array detail-key collision (DG-7)

Four raises already carry both `owner` and `operation`:
`lib/array.x:61`, `lib/typed-array.x:66`, and line 13 of
`unittest/compiler-fixtures/array-generator-family.x` and
`array-generator-family-live.x`. `owner` identifies the Array type;
`operation` is an action Symbol such as `<push>` or `<take-last>`.
Renaming `owner` to `operation` would create two entries with the same key.
These four raises retain their current details while the other D2 keys move.

The unaffected key migration is `14973621`: 105 files, `.x` +197/-192.
The four raises and their retained Array reader are byte-identical.
Current-tree focused verification passes 940 tests, 1,082 fixtures,
CLI probes, 384 book samples, 101 outputs, commands, and packages.
The migration changes no Error cause or existing detail value.

Gary must choose the resulting detail shape: combine type and action into
one `operation` String, or retain the type as `operation` and name the action
with another key. The first option changes the current action value; the
second needs a vocabulary decision. No conflicting raise was changed.

### Stage 2 D3: autodiff fixture expectations (resolved)

The original `make packages-check` failed on the generated C expectations of
`autodiff-forward`, `autodiff-control-flow`, and `autodiff-reverse`.
Each delta replaces the fixture header include with a generated guard and
direct runtime and native includes. No Error cause differs in these deltas.

The candidate at `9511153f` completed 9/9 autodiff fixtures with three
failures. Restoring every D3 file to `7e382f738`, running `make build-safe`,
and running `make -C packages/autodiff fixtures` reproduces the same three
C deltas, completing 3/9 fixtures before stopping. The baseline compiler
reports its shipped `lib/x2c.xi` prelude.
The failure therefore predates D3. Rule 6 forbids changing these fixture
expectations to make the check pass.

Evidence in `/tmp/x2c-standard-d3/debug/`: `d3-packages-check.log`,
`d3-autodiff-baseline.log`, `d3-baseline-build-safe.log`, and
`d3-baseline-env.log`. The original candidate left expectations unchanged.

Independent commit `fb7004db` corrected the three expectations. The D3
retry starts from `origin/dev` at `e4d22fc7` and replays only D3 as
`0b9c45b0`. `make packages-check` passes, including all 9 autodiff
fixtures and 19 checked artifacts. This worker changed no expectation.
The package blocker is resolved. D3 delivery commit: `f7f886ad`.
The D2 detail-key collision remains open.

Retry evidence is in the managed `standard-d3-retry/x2c` worktree under
`debug/d3-retry-packages-check.log`. The initial book-example failure was
a missing local PCRE2 archive, resolved by the existing package targets.

### Stage 4: subject spelling and generated C (NM-2)

Renaming `Job._open_streams`'s subject from `job` to `j` changes only
its generated C parameter and four bound references in `lib/process.c`.
The native build passes, but `make stage-diff-0` fails because the plan
requires byte-identical C/H against the current bootstrap. The other 219
files remain identical. The rename is restored; two call wraps pass the
same comparison over all 220 files.

Evidence in `/tmp/x2c-standard-docs/debug/`:
`stage4-process-name-c.diff`, `stage4-process-name-all-diffs.txt`, and
`stage4-process-restored-diff.log`. Gary can authorize review of these
binding-only C changes and the normal bootstrap refresh, or leave this
NM-2 finding pending. This trial does not reject other possible repairs.

### Stage 4: runtime renames and a macro body change generated output

The pre-edit `make build-safe` and `make stage-diff-0` at `ff68eaaa`
pass, comparing 220 C/H files. Three violation repairs fail that exact
comparison and have been restored:

- `lib/match-cache.x:323`: renaming the `MatchLease._plan` subject from
  `lease` to `m` changes its C prototype, definition, and member accesses.
- `lib/match.x:759`: renaming the `MatchWalk._first` subject from `walk`
  to `m` changes its C prototype, definition, and four receiver accesses.
  No Error-site position changes in this attempt.
- `lib/varconvert.x:92`: removing a single-statement body's braces removes
  a nested generated C block around `$error.source.numeric` and shifts
  nine later Error-site line numbers by one. The macro expands to a local
  declaration and a raising block.

Stage 4 requires a byte-exact stage comparison without rebaselining. These
two subject renames do not preserve generated C parameter spellings.
The direct brace repair also changes reported source positions.
No replacement algorithm, new helper, or padding
was introduced to hide a delta; five independent comment and width repairs
pass their per-file comparisons.

Gary must decide whether reviewed identifier-only C changes and source
position changes can use a different neutral proof, or whether these three
violations remain pending. The source and lint baseline retain them.

Evidence in `/tmp/x2c-standard-d2/debug/`: `runtime-baseline-stage-diff-0.log`,
`runtime-match-cache-diff.log`, `runtime-match-name-diff.log`, and
`runtime-varconvert-diff.log`. Pre-edit C/H and rejected patches and C are
preserved in `.context/` in that worktree. No bootstrap was refreshed.

### Stage 4: one report-macro statement has a generated C scope (ST-1)

At `ff68eaaa`, `src/literals.x:229` encloses
`$report.parse.insert_name` in explicit `if` braces. Removing those braces
changes only the generated `Compiler__parse_named_reference` C block and
scopes of its two report-macro locals. The attempt fails `make stage-diff-0`;
its header is unchanged. The braces are restored. Search wrapping and the
encoding comment pass both stage comparisons across all 220 C/H files.

Evidence in `/tmp/x2c-standard-lint/debug/`:
`stage4-literals-attempt1.c.diff`, `stage4-literals-attempt1.h.diff`,
`stage4-literals-after-diff0.log`, `stage4-literals-indent-diff0.log`, and
`stage4-literals-indent-diff1.log`. No bootstrap expectation changed.

Gary must choose whether this explicit macro scope is an ST-1 exception,
or permit the reviewed scope-only C delta. This attempt does not establish
that every alternate spelling changes C. Other violations continue.

### Stage 4: expression cleanup changes retained source coordinates

All eight remaining findings after the initial expression delivery were
tested independently at the fixed worker base. Every probe builds.
The CM-2 comment at original line 789 now explains resolved reference
reads without repeating `_final_value_type`; the ordinary wording happens
to retain the original byte length. Both complete 220-file C/H comparisons
pass. Expression violations now fall from the original 16 to seven.

- LY-3 at 128 adds one to six retained macro lines and seven to their
  byte offsets, and changes two `X2CErrorSite` lines 564/578 to 565/579.
- LY-3 at 502 keeps line counts but adds one to each of those six macro
  byte offsets. LY-2 shortening at 963 subtracts ten from those offsets.
- Each ST-1 brace removal at 595, 2816, 3815, and 3818 changes a nested
  C scope around report-macro locals; the first also changes retained
  coordinates. The macro owners in `src/expressions-reports.xmacro`
  at 31, 173, 301, and 289 explicitly contain a nested block. Unlike
  the callables and regions expansions, these are valid single
  statement expansions and all four brace removals build.

All seven failed comparison edits are restored; their headers remain
unchanged. Gary must choose coordinate and expansion-scope exceptions
or authorize the separately reviewed generated changes. No expectation
was changed. A failed spelling does not reject every possible alternative.

Evidence in `/tmp/x2c-standard-lint/debug/` includes
`stage4-expressions-isolated-results.txt`, the separate
`stage4-expressions-isolated-*`
build logs and C/H diffs, and `stage4-expressions-isolated-final-*`
proof logs. The earlier combined attempt remains preserved in
`stage4-expressions-attempt1.{c,h}.diff`, but is superseded by these
individual results.

### Stage 4: leaf-ledger accessors require declarations (FI-6, MO-6)

Deleting the three `Symbol` declarations at `src/ast.x:303-307` fails
`make build`: `ast`, `emit`, `macros`, and `transform` cannot resolve
`compound_operator`, `binary_precedence`, or `compound_assignment`.
Their definitions live in the separate `src/operator-ledger.x` unit,
which includes `compiler.x`. Deleting the two `Type` table accessors at
`src/type.x:803-804` also fails `make build`: `fixed_var_tag` and
`var_tag_row` see untyped table calls and cannot index their results.
Their definitions live in `src/type-ledger.x`, which includes `type.x`.
The initial grouped removals and all five subsequent individual removals
are restored. Each individual removal fails `make build` with the
corresponding missing method or untyped table indexing result.

FI-6 disallows these declarations in `src/`. MO-6 requires large ledgers
in units nothing includes. Importing either implementation into its
consumer would change that ownership boundary and is not attempted.
Gary must choose a leaf-accessor exception or another dependency design.
Continue unrelated repairs; no bootstrap or fixture expectation changed.

Full failure logs in `/tmp/x2c-standard-lint/debug/`:
`stage4-ast-build.log` and `stage4-type-remove-build.log`. Individual
evidence is in `stage4-ast-individual-{compound,assignment,precedence}`
build logs, `stage4-type-individual-{builtin-tags,tag-rows}` build logs,
and the individual results files. Restored `make build` and the complete
220-file `stage-diff-0` pass in `stage4-ledger-individual-restored-*`.

### Stage 4: linked compile-time builder needs a native declaration (FI-6)

Removing `src/builtins.x:21` and its ownership comment fails `make build`.
The included `lib/meta.x` declares `x2c_param_make` as compile-time-only;
without the native declaration, ordinary built-in implementation calls
report that it can only be called at compile time. The native definition
is the generated copy in `src/linked-meta.x`. The declaration and comment
are restored. Changing that compiler/native boundary is not attempted.

Gary must choose whether this linked copy permits an FI-6 exception or
requires another explicit dependency design. Evidence:
`/tmp/x2c-standard-lint/debug/stage4-builtins-declaration-build.log`.
Continue unrelated wrapping repairs; no generated expectation changed.

### Stage 4: cleanup declaration and coordinate constraints

Each of the seven `cleanup.x` declarations was removed independently.
The four try/catch slot declarations at lines 630-633 cause unknown or
forward-referenced macro errors at their templates. Removing line 634
(`builtin_try_cleanup_placement`) fails native binding resolution in
`builtins.x`. Removing `builtin_defer_record` (859-860) or
`builtin_defer_captures` (861) builds but changes only retained line and
byte coordinates in `cleanup.c`; each header is identical. All seven
removals are restored. FI-6's collection-before-expansion exception names
`lib/` only; Gary must choose whether these `src/` slots also qualify.

Wrapping the width-81 comment at line 51 and the call at 871 independently
builds but changes only retained coordinates in `cleanup.c`; headers are
identical. Both edits are restored pending the coordinate-only choice.
Three other calls and the repeated blank line are repaired. A readable
quotation opening preserves the callback's source line; all 220 C/H files
are identical through stages 0 and 1.

Evidence in `/tmp/x2c-standard-lint/debug/`: the seven
`stage4-cleanup-builtin_*` build, comparison, and C/H diff logs;
`stage4-cleanup-declaration-results.txt`; `stage4-cleanup-width*`;
`stage4-cleanup-defer-wrap*`; and `stage4-cleanup-final-diff0.log` and
`stage4-cleanup-final-diff1.log`. No expectation changed.

### Stage 4: transform coordinates and report-macro scopes

- The LY-3 wrapping at original `src/transform.x:771` builds, but changes
  the retained anonymous macro line 793 to 794 and byte offset 29257 to
  29276. Its header is unchanged. Restore that isolated edit. Gary must
  choose a source-coordinate exception or authorize this generated delta.
- Each ST-1 report invocation at original lines 1436, 1533, 1566, 1580,
  and 1623 was tested separately. Each builds, but removes one nested C
  scope around report-macro locals. Headers remain unchanged. Restore
  all five edits. Gary must choose an ST-1 exception for these expansion
  scopes or authorize their separately reviewed generated differences.
- The shape argument wrapping at original line 802 passes both complete
  220-file C/H comparisons. Transform violations fall from seven to six.
- Evidence: `debug/stage4-transform-probe-results.txt`, the separate
  `stage4-transform-{statement-wrap,string,numeric,container,operand,index}`
  build logs and C/H diffs, and `stage4-transform-final-*` proof logs.

### Stage 4: callables source coordinates, names, and macro statements

- All four `src/callables.x` violations were tested independently.
  Wrapping at 297 changes retained macro lines 335, 357, 349, 353,
  and 960 by one and their byte offsets by 11. Wrapping at 874 changes
  macro line 960 by one and byte offset 35869 to 35876. Headers are
  unchanged. Restore both edits; Gary must choose a coordinate exception
  or authorize these generated differences.
- Renaming only the `Callback.split` subject binding from `cb` to `c`
  builds, but changes its generated parameter declaration and uses.
  Restore that isolated edit. Gary must choose an NM-2 exception or
  authorize this binding-preserving generated spelling change.
- Removing the braces at 1314 fails `make build`: `parse: expected one
  statement`. `$report.callback.arity` expands a local declaration and
  call, not one statement. Restore the edit. Gary should review a
  detector false positive under ST-1, which requires braces for two or
  more statements, or authorize a macro change. The owner is
  `src/callable-reports.xmacro:60`: a `String detail` declaration and
  a `_fail` call. The book rule is
  `docs/src/guide/macros.md:404-408`: a direct guarded body must be one
  statement; an unwrapped sequence does not qualify.
- No callables source edit remains. Violations stay at four. Restored
  `make build`, `stage-diff-0`, `stage-1`, and `stage-diff-1` pass, with
  all 220 C/H files equal. Evidence: the separate
  `debug/stage4-callables-{factory-wrap,shape-wrap,subject,arity}` build
  logs and C/H diffs, `stage4-callables-probe-results.txt`, and final
  proof logs.

### Stage 4: region report-macro statement count

- Removing only the ST-1 braces at original `src/regions.x:899` fails
  `make build` with `parse: expected one statement`. The report macro
  expands a `String message` declaration and a `warn` call; the owner is
  `src/region-reports.xmacro:26`. The same book rule in
  `docs/src/guide/macros.md:404-408` excludes an unwrapped sequence from
  direct guarded bodies. Restore that edit. Gary should review
  whether this is a detector false positive under ST-1, which requires
  braces for two or more statements, or authorize a macro change.
- The CM-2 comment at 1348 now explains the resolved direct-call
  signature instead of repeating `_parameter_types`. Violations fall
  from two to one; all 220 C/H files match in both comparisons.
- Evidence: `debug/stage4-regions-escape-build.log`, the before/final
  census files, and `stage4-regions-final-*` proof logs.

### Stage 4: protocol ledger declarations and quoted block

- Removing each FI-6 declaration at original `src/protocol.x:1632` and
  1634 separately fails `make build`; compiler consumers lose the
  corresponding `Compiler.operator_member` or `derived_member` method.
  Both definitions are in `src/operator-ledger.x:32` and 42. That leaf
  includes `compiler.x`; adding a reverse include conflicts with MO-6.
  Restore both removals. Gary must choose a leaf-ledger declaration
  exception or authorize another ownership boundary.
- Removing only the ST-1 braces inside the quotation at 2422 builds,
  but changes the retained AST from a block to a statement and a later
  macro byte offset 89180 to 89176. Headers are unchanged. Restore the
  edit. Gary must choose a quotation exception or authorize the reviewed
  AST and coordinate changes. No protocol source edit remains; all
  three violations remain.
- Evidence: `debug/stage4-protocol-probe-results.txt`, separate
  `stage4-protocol-{operator-declaration,derived-declaration,fallback}`
  logs and diffs. Restored final four-target proof logs compare all
  220 C/H files unchanged.

### Stage 4: compiler support respellings change generated bytes

The support slice starts at `ff68eaaa`. Its unedited
`make stage-diff-0` passes for all 220 C/H files. Five violations remain
held after focused attempts; the affected edits were restored.

- `src/symbols.x:589`, ST-1: removing the single-statement braces in
  `_check_spelling` changes the emitted `if` body from a C block to a bare
  statement, and joins the following declaration in the generated layout.
- `src/compiler.x:1859`, ST-1: removing the `else` braces in
  `_update_brace_stack` changes the C block and moves the later completion
  error's `X2CErrorSite.line` from 1946 to 1944.
- `src/meta-helper-client.x:120` and `:365`, NM-2: shortening the two
  `Call` subject bindings from `call` to `c` changes only their generated
  prototype and body parameter spellings, but fails byte comparison.
- `src/meta-sdk.x:307`, LY-2: wrapping the 80-column `foreach` header and
  body changes only `MetaContext_reject`'s later error site from line 633
  to 634. A layout-form alternative is not accepted inside this brace-style
  file; ordinary wrapping builds successfully but fails the comparison.

The failed command for each built attempt is `make stage-diff-0`.
Evidence is under `debug/` in the private compiler-support worktree:
`symbols-stage-diff-0.log`, `compiler-stage-diff-0.log`,
`meta-helper-client-stage-diff-0.log`, and
`meta-sdk-stage-diff-0-wrapped.log`. Exact helper and SDK generated deltas
are in `meta-helper-client-generated.diff` and `meta-sdk-generated.diff`.
Successful edits in these and other files pass the original stage-0 and
stage-1 comparisons. No bootstrap, fixture, or lint baseline was changed.

Gary must decide how byte-identical proof applies to these respellings:
authorize these reviewed generated differences with a fresh bootstrap,
or retain the five violations. Changing the proof rule or accepting a
source-location difference requires his decision. Other violations continue.

### Stage 4: macro expression wrap changes a diagnostic location

One violation remains at `src/macros.x:4023`: `wrapped-opening-line`
(LY-3), in `Compiler._statement_expression`. Moving the outer call's
arguments to a continuation adds one source line. The generated
`src/macros.c` then changes only `_lisp_import_hook`'s ErrorSite line
from 4040 to 4041. `make build` passes, but `make stage-diff-0` fails.
The attempted wrap was restored. A two-line form with all arguments on
its continuation would use 85 columns, exceeding LY-2.

Evidence is in the private parser worker's `debug/`:
`macros-wrap4023-build.log`, `macros-wrap4023-diff0.log`, and
`macros-wrap4023-generated.diff`. This rejects the tested wrap under the
required byte comparison; it does not reject all possible repairs.

Other existing findings admit neutral repairs. Two line-preserving wraps,
a paired width and stacked-blank repair, and deletion of four redundant
name-restating comments with four wraps reduce macros from 14 violations
to one. The parse repair reduces one violation to zero. Both complete
stage comparisons pass for the retained changes, covering 220 C/H files.
No stage expectation, lint baseline, or bootstrap file changed.

Options for Gary: retain this violation, or permit a reviewed generated
refresh for this diagnostic location. No padding was added to offset it.

## Progress

| Stage | Commit | Date | Result |
| --- | --- | --- | --- |
| Standard written | `43ff6c34`, `fd88fae4` | 2026-10-04 | PR #164 merged |
| Plan made executable | `7e382f73` | 2026-10-05 | decisions accepted |
| D5 | `aab9edd4` | 2026-10-05 | static fails; restored build passes |
| Stage 1 | `4cfa524f` | 2026-10-05 | 384 samples; 101 outputs pass |
| 3.1 | `83bbb850` | 2026-10-05 | 68 IDs; 98 ID-only finding changes |
| 3.2 | `99781621` | 2026-10-05 | 24/25 name boundaries pass |
| 3.3 | `814684bb` | 2026-10-05 | 10 codes; 11 positive findings pass |
| 3.4 | `b7719c78` | 2026-10-05 | 6 invalid cases; suppressed fix unchanged |
| 3.5 | `f7b1b6a6` | 2026-10-05 | 11 codes; 287 new candidates |
| 3.6 | `9542ea14` | 2026-10-05 | 32 codes; 106 violations |
| 4.process | `e70355e7` | 2026-10-05 | 3 -> 1; +4/-4 .x |
| 4.emission | `5f8e5484` | 2026-10-05 | 6 -> 0; +16/-14 .x |
| 4.match | `33c6f09e` | 2026-10-05 | 5 -> 2; +3/-3 .x |
| 4.targets | `a731b530` | 2026-10-05 | 1 -> 0; +1/-1 .x |
| 4.parser | `351486a6` | 2026-10-05 | 39 -> 9; +55/-52 .x |
| 4.lowering | `ca52c661` | 2026-10-05 | 26 -> 17; +20/-18 .x |
| 4.binding | `2efad5a6` | 2026-10-05 | 5 -> 2; +2/-3 .x |
| 4.meta | `e7dabbee` | 2026-10-05 | 2 -> 0; +5/-4 .x |
| 4.cli | `37eababa` | 2026-10-05 | 2 -> 0; +3/-2 .x |
| D2 partial | `14973621` | 2026-10-05 | +197/-192 .x; four raises held |
| D2 held | `a7c271f` | 2026-10-05 | +197/-192 .x; 4 raises held |
| D3 | `f7f886ad` | 2026-10-05 | 9/9 autodiff; +9/-9 .x |
| D3 held | `9511153f` | 2026-10-05 | +9/-9 .x; package check fails |

D3 retry on `e4d22fc7`: safe rebuild, verify (940 tests and 1,082 compiler
fixtures), CLI probes, book examples (384 samples and 101 outputs), separate
book outputs (101), commands, and packages pass. Autodiff passes all nine
fixtures and 19 artifacts. No fixture or lint baseline changed.

Stage 4 rows record violation counts and authored `.x` line changes.
Process, Match, and target repairs compare all 220 C/H with the bootstrap.
Emission repairs also compare stage 0 with stage 1. Emission commits:
`5fc3fe75`, `5f8e5484`. Match commits: `7fcd0023`, `c5a66fc7`, `33c6f09e`.

Parser repairs compare all 220 C/H files at stages 0 and 1.
The complete 108-file census falls from 94 violations to 64.

Lowering repairs pass complete 220-file stage comparisons.
The complete census now has 55 violations.

Binding repairs pass complete 220-file stage comparisons.
The complete census now has 52 violations.

Meta repairs pass complete 220-file stage comparisons.
The complete census now has 50 violations.

Cli repairs pass complete 220-file stage comparisons.
The complete census now has 48 violations.

Stage 3.5 census: 108 compiler and runtime files. The baseline took
10.63 seconds; the candidate took 10.61 seconds. All 1,599 original
findings remain byte-exact. Authored `.x` changes: +403/-2.

Stage 3.6 measured `/usr/bin/time -l make commands-check`: 17.44 seconds
before the ratchet, 26.99 seconds after it. The observed increase is
9.55 seconds. Higher counts fail; lower counts print the proposed line.

Later detector work: typed-AST builders and `Type.method(x)` receivers
remain deferred, as stage 3.5 specifies.

## Plan review

- Established facts: the standard restates contracts their owners already
  enforce. No stage adds a consumer check.
- Reuse and deletion: stage 1 deletes duplicate rule text from about
  fifteen files. Stage 3 extends the existing lint engine and its existing
  smoke test. The only new lasting mechanisms are the suppression comment
  and the baseline file, which D4 requires.
- Idiom: the rules describe x2c as written on `dev` after the 2026-09
  campaigns, including the corrections those campaigns made.
- Validators, diagnostics, negative fixtures: D2 and D3 change existing
  raises only. The lint detectors are advisory candidates; only the
  ratchet over existing violation codes fails publication.
