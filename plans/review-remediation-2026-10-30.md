# Repository repairs from the October 30 review

> Status: active
> Written 2026-10-30 against `dev` `ae3739230`. Gary selected a remediation
> plan on 2026-10-30 and accepted the recommendation on every question
> under "Decisions" the same day. Batches 1 and 2 are in progress; no batch
> has been published. Findings and verification are in
> [the review record](reference/review-2026-10-30.md).

## Result and scope

Repair the reproduced defects and the drift the review found in the month
of rapid work since 2026-09-30: two code defects in this week's `--cpp` and
REPL changes, publication-gate gaps, stale release notes and site text, and
guidance that teaches removed rules. Keep public runtime signatures. Change
authoritative sources and regenerate derived artifacts through existing
targets. This plan adds no recurring gate, test requirement, or planning
step; the one gate change it proposes is a question for Gary (Q2).

The [language-reference writing plan](review-remediation-2026-10-11.md)
keeps its separate scope. This plan owns only the October 30 findings.
Items the review marked plausible are repaired only after a probe confirms
them; the probe is named with the item.

## Evidence at the baseline

The review built nothing and ran nothing. Each row was read at `ae3739230`.
The record holds the full list and the clean areas.

| Finding | Verified observation |
| --- | --- |
| A-1 | `Cpp.copy` (`src/cpp/cpp.x:85-96`) copies `touched` but shares `before`; `_close` (`src/cpp/conditions.x:97`) installs `before` as the live table. |
| A-2 | `_worker_serve` (`commands/repl/repl-worker.x:340-380`) has no catch before dispatch; the fork runs inside `repl_run`'s `try` (`repl.x:584-586`); no atfork reset exists. |
| A-3 | `repl-program.x:912-913,949` append manifest inputs to the stored roots that `:reload` echoes back (`repl.x:359-373`). |
| A-10 | `src/frontend.x:579-581` sets `cpp.cpp`, and `tokens.x:40` expands whenever `c.cpp` is set. |
| A-15 | The lint census lists entries only; five member lines exceed 79 columns today. |
| B-1 | `doc-check` runs `check-docs` and the llms check only; `gate-state.py:340-341` adds `doc-outputs` on another path. |
| B-3 | `tools/land-dev:30-35` accepts `bootstrap/{lib,src}/*.{c,h}` only; 47 nested headers are tracked. |
| B-4 | `Makefile:90-115` keys the generator stamp on inputs that exclude the two tracked outputs. |
| D-1 | The Unreleased notes omit the find/index break, `$switch` removal, `--cpp` default, and the REPL rewrite; two links point to deleted sections. |
| D-3 | `site/src/content/home.md:19,40-41` advertise `Slice`, compile-time Lisp, and a bytecode interpreter. |
| E-1 | `agents/x2c-code-standard.md:1004-1005,1328` reject `$(...)` and `@(...)`; two guides teach the deleted `$refusal`/`$decline`. |

## Decisions

Gary accepted the recommendation on every question on 2026-10-30. Each
entry keeps the question, the recommendation now selected, and the
alternative that was not chosen.

**Q1. Macro argument commas under `--cpp`.** `src/cpp/expand.x:276-339`
groups commas inside `[]` and `{}`; the book promises C99 rules
(`docs/src/reference/language.md:4654`). Recommendation: since `--cpp` now
serves existing C, group only parentheses and keep the book's promise. The
alternative is to document the deviation.

**Q2. Output checks in the docs-only gate.** A book edit that breaks a
`text` output fence publishes green through `ensure doc-check`. Any repair
adds build time to the docs-only gate, which needs approval under the
process ceiling. Recommendation: `gate-state.py ensure doc-check` runs
`make -o build doc-outputs` only when a changed path is under `docs/src/`
and contains an `x2c` fence, reusing the existing classifier branch; the
integrator's `gate_for` adopts the same classifier so both tools agree.

**Q3. Worker push policy.** `AGENTS.md` says workers never push;
`tools/hooks/pre-push` blocks only `dev` and `main`, and `context` accepts
`worker/direct` and `worker/pr`. Recommendation: reject role `worker` with
any delivery other than `private`, and block every push for a
`worker/private` context. The alternative is to reword `AGENTS.md`.

**Q4. Attribute macros in generated declarations.** `c-prefix-macros`
pins `int weak_value = 5;` for a `WEAK`-prefixed definition, so
`__attribute__((weak))` and `visibility("default")` are dropped
(`language.md:4738-4745` documents "contributes nothing"). Recommendation:
emit the macro name as written so the C compiler keeps the attribute;
update the fixture and the sentence. The alternative keeps the current rule
and adds one sentence that the link attribute is lost.

**Q5. Internal-tier operations in the storage chapter.**
`docs/src/guide/storage-ownership.md` teaches `Scope.owner` and
`Block.move_to`, which `docs/library-api-tiers.txt:20,198` mark internal.
Recommendation: move both to the `advanced` tier, since the chapter exists
to teach them. The alternative rewrites the chapter around primary
operations.

**Q6. Gallery slug.** `magic-05-compile-time-lisp.md` (slug
`compile-time-lisp`) shows a `meta` function. Renaming changes a public
URL. Recommendation: rename to `compile-time` and add a redirect entry if
the site supports one; otherwise keep the slug and fix only the prose.

**Q7. Unrecorded signature changes.** Confirm that these were intended, so
the release notes can record them as accepted breaks: `FileReadStatus`
from int enum to `Symbol` (`lib/file.x:65`, f6554b722); `String.try_long`,
`String.try_double`, `Symbol.try_new` from `T *` to `T &?` (972011139);
pointer-to-reference changes in 3652922bd; `List @fields` on
`String.format`, `Logger.*`, and `log_*` (6889d5b18). Recommendation:
record all four; none has an in-repo caller left behind.

**Q8. Notes lock scope.** `plans/notes-accounting-and-database-thread.md:28-30`
says Map construction and tag parsing happen outside the mutex; only
`get_note` does that (`notes.x:108-118,158-159,169,183`). Recommendation:
narrow the plan's statement to the lookup route and keep the code; moving
the other handlers' work outside the lock is a separate measured change.

## Repairs, ranked by consequence

Each repair names its owner, the change, and its acceptance evidence.
Letters match the review record.

### Batch 1. Compiler and runtime (full gate)

**R1. Give each copied conditional group its own `before` table (A-1).**
Owner: `Cpp.copy` in `src/cpp/cpp.x`. Copy `group.before` beside
`group.touched`. Add one `--cpp` fixture with an `#include` inside an
undecided group followed by a `#define` and a dependent `#ifndef` arm, and
check the collected declaration against the full parse. Keep the
"independent" sentence true.

**R2. Stop the expansion pass in host-symbol modes (A-10).** Owner:
`_tokenize_cpp` in `src/frontend.x`. Delete the `cpp.cpp = Cpp.new({})`
line and its comment. Acceptance: the `--cpp-symbols`, `--live-symbols`,
and bind fixtures are unchanged.

**R3. Clear `cpp_expansion` for the prelude with `--no-cpp` (A-11).**
Owner: `Frontend.load_prelude` in `src/frontend.x`. Derive the effective
mode once and reuse it in `_begin_unit`. Acceptance: with `--cpp --no-cpp`
the prelude interface is replayed, shown by the header-cache probe.

**R4. Decide `#if` corners the way the C compile does (A-12).** Owner:
`src/cpp/conditions.x`. Sign-extend single-character constants to match
`-fsigned-char`; leave multi-character constants, shifts of 64 or more,
and `LONG_MIN / -1` or `% -1` undecided. Extend the condition fixture with
`#if '\xff' < 0`, a two-character constant, `1 << 64`, and the division
edge.

**R5. Keep `command_macros` to its contract (A-14).** Owner:
`collect_native` in `src/frontend.x` and the field comment in
`src/compiler/compiler.x:170-176`. Store the host `-dD` table in a field of
its own, or sort it and widen the documented meaning. Acceptance: the REPL
native tests pass and the field comment matches every writer.

**R6. Macro argument commas (A-13).** Q1 selected C99 grouping.
`_track_group` groups parentheses only; the `COUNT((int[]){1, 2})` case
joins the expansion fixtures and the book sentence stays.

**R7. Attribute macros (the record's C section).** Q4 selected keeping
the attribute. Owner: the prefix-macro reading in `src/parse` and the
declaration emission it feeds. Emit an attribute-bodied prefix macro's
name as written, only in the defining unit's own C where its `#define`
passes through; generated headers keep their current text, because other
units do not see the macro. Update `c-prefix-macros.{c,h}` and the
sentence at `language.md:4738-4745`. If the emission site cannot tell the
unit's C from its header, stop and report instead of guessing.

**R8. Runtime contract corrections (A-17).** Owners named per item.
- `lib/net.x:148-149`: delete `return NULL;` after `_io`.
- `lib/array/generics.x` `push`, `unshift`, `insert`: add `<void-op>` to
  `Raises:` and check null before the boxed-void test in all three.
- `lib/map/generics.x` `setdefault`, `set`: add `<void-op>` to `Raises:`.
- `lib/array/array.x:131` `updateindex`: add the `Raises:` paragraph from
  `postfixindex` plus `<void-op>`. The `setindex` asymmetry is recorded,
  not changed.
- `lib/http.x`: add `Raises:` to `HttpResponse.header`, `HttpServer.new`,
  `HttpServer.start`, `Http.fail`, and `HttpRequest.read`; replace `_decode`
  and `_query` with `Url.parse_query` and `String.percent_decode`, mapping
  `<malformed>` to a 400 whose message names the URL, not JSON; delete the
  `HttpResponse.init`, `Router.init`, and `HttpServer.init` bodies after a
  probe confirms the explicit `new` suppresses the init requirement.
- `lib/json.x` `x2c_json_write` and `lib/net.x` `x2c_net_accept_fd`:
  rename to `_x2c_*`, change `/**` to `/*`, drop their tier rows.
- `lib/list-selectors.x:30`: drop "as a `List`".
- `lib/array/generics.x`: rename `find_element` to `index_element` and
  update `unittest/compiler-fixtures/array-generator-family.symbols`.
- `src/expressions/syntax.x:195`: call `Type.is_optional_reference`.
- `lib/typed-list.x`: add one `ListInt.find` assertion to
  `unittest/test-typed-list.x`; generate `find` only if the assertion fails.
- Wrap the lines over 79 columns and add the missing blank lines the record
  lists in `lib/http.x`, `lib/time.x`, `lib/json.x`, `lib/typed-list.x`,
  `lib/net.x`.
Then `make doc-generate`.

**R9. Remove the unused staging entry point (A-7).** Owner:
`Compiler.stage_session_function` in `src/meta-group/staging.x`. Move
`commands/repl/tests/inspect-check.x` to `emit_session_function`, delete
the function, and regenerate the compiler API pages.

**R10. Segment arm stacks (A-19).** Probe first: a header whose selected
arm contains an include and whose `#else` arm holds C++ text, built without
`--cpp`. Repair only if the shallow parse accepts or misreports that text:
seed each segment's plain scan with the arms open at its start.

### Batch 2. Commands: repl, lsp, lint, graph (independent command checks)

**R11. Fence the forked worker (A-2).** Owner: the child branch in
`repl_worker_start`, `commands/repl/repl-worker.x`. Wrap the child body in a
catch-all that sends `{status: failed, message}` on the reply pipe and
`_exit`s, so no raise reaches supervisor frames. Add a `terminal.py` case
that deletes the snapshot before `:reset` and expects "session unchanged"
with the live session intact.

**R12. Keep manifest inputs out of the stored roots (A-3).** Owner:
`repl_program_build_selected` in `commands/repl/repl-program.x`. Store only
user-selected roots in `program.roots`; derive manifest inputs on each
build. Add a `program.sh` case that loads a manifest with a static-library
dependency and reloads twice, checking `:files` shows one `root:` line per
root.

**R13. Record recovery as a transcript boundary (A-4).** Owner: `_recover`
in `commands/repl/repl.x`. Call `_record(client, ":reset")` after a
successful restart. Add a `terminal.py` case: crash, redeclare, `:save`,
`:replay`.

**R14. Remove failed candidate directories (A-5).** Owners:
`repl_program_build_selected` failure returns and the worker's failed
frame. Remove `program.directory` on every failure return; send the
directory in the failed frame so the supervisor removes it after a forced
kill. Set `TMPDIR` in `playground.py` and `terminal.py` to a per-run
directory and assert it is empty at exit.

**R15. Key the submission cache on content and prune it (A-6).** Owner:
`commands/repl/repl-native.x:311-330`. Hash the generated header text and
the program's content identity instead of its temp path; prune `repl/`
with the existing `scripts/` policy.

**R16. REPL dead code and small defects (A-7).** Delete
`ReplSession.complete_functions`, `ReplSession.symbols`, `_bare`,
`ProgramBuild.archives`, the discarded `directory` in `_program_exports`,
the test-only `repl_program_build` wrapper, and the no-op
`repl_program_close`; simplify `repl_worker_close` to the exited path; fix
the overwritten `<malformed>` diagnostics in `_submit_native`; clear
`worker.failure` on the early return at `repl-worker.x:199`; restore
`client.replaying` under `defer`; say "prompt function" for `:ast` in help
and `repl.md`; add `:quit` to both command tables. On Linux, probe GNU ld
`--trace` output before changing the `-l` recording at
`repl-program.x:827-835`.

**R17. Language server (A-16).** Owner: `commands/lsp/lsp.x` and members.
Return early from `_publish` when `server.exiting`; delete the three
redundant `retain` calls; add `>` to the completion trigger characters;
serve a script's document text from `w.sources` rather than the rewritten
compiler text, after a probe shows line 0 is wrong today. Extend
`features.py` with an `exit`-without-`shutdown` case.

**R18. Lint member coverage and line mapping (A-15).** Owner:
`commands/lint/x2c-lint.x` and `declarations.x`. Run the token and comment
rules over each spliced member's own text; map parse-based findings
through `c.token_source` and skip rows from other files, as
`_source_index` does; use `Compiler.driver_executable()` in `--fix`. Fix
the five over-width member lines the record names so the census returns
to zero. Add a lint fixture with a function preceded by an expanding C
macro (the untested 10-29 span mapping). Print `--help` to stdout and give
`commands/lint/README.md` an overview and maturity sentence.

**R19. Graph command (record B, commands).** Print the `usage:` line
first and `--help` to stdout in `commands/graph/graph-output.x`; record
`cpp_expansion` in snapshot configurations; use `x2c_get_executable()` in
`status`; fix the unreachable `explorer/data` default in
`tools/partition/build-data.py`.

**R20. Experimental command availability.** Say in `docs/src/reference/cli.md`
(lint rules), `docs/src/guide/regions.md` (`x2c-graph certify`), and
`docs/src/guide/repl.md` that these commands are checkout-only and not
installed, as `cli.md:861-863` does for bind. Mark experimental commands in
`x2c help` output (`src/cli/help.x:211-229`) if the help fixture change is
accepted; otherwise leave the listing.

### Batch 3. Build and process tooling (tool tests and focused checks)

**R21. Classify `commands/` before Markdown (B-2).** Owner:
`tools/gate-state.py:326-336`. Test the `commands/` prefix first so a
`.md` fixture under a command runs `commands-check`. Add the case to
`tools/test-gate-state.py`.

**R22. Output checks for docs-only publication (B-1).** Q2 selected the
narrow addition. Extend `ensure doc-check` and `gate_for` from one shared
classifier that adds `make -o build doc-outputs` only when a changed path
under `docs/src/` contains an `x2c` fence, and add tests for both tools.

**R23. Accept nested bootstrap headers in `land-dev` (B-3).** Owner:
`tools/land-dev` `generated()`. Test the `bootstrap/lib/` and
`bootstrap/src/` prefixes with the `.c`/`.h` suffixes. Add a unit test
with a nested header path.

**R24. Key the generator stamp on its outputs too (B-4).** Owner:
`Makefile:90-115`. Record `cksum $(META_OUTPUTS)` after generation and
delete the stamp when the outputs no longer match. Acceptance:
`git restore src/linked-meta.x` followed by `make build` regenerates it.

**R25. Hook and role policy (B-5).** Q3 selected the strict policy.
`agent_context.py` rejects role `worker` with any delivery other than
`private`, `pre-push` blocks every push for a `worker/private` context, and
`test-integrate-dev.py` covers `worker/private` and a push to `main`.

**R26. Document and narrow the configure hook write (B-6).** Owners:
`Makefile:70-77`, `docs/src/internals/building.md:19-21`,
`agents/quick-start.md:35-38`. State that `make configure` sets
`core.hooksPath` once in the shared repository configuration and that every
worktree runs the main checkout's hook. Keep the relative `tools/hooks`
value.

**R27. Tooling corrections (B-7).** Record `builds/0/x2c` in the
`doc-check` record or make `doc-check` depend on `build`; regenerate
`tools/version-viewer/snapshots.js`; add `apps` to the
`tools/test-examples.py` stub; wire the cheap `tools/test-*.py` scripts
into an existing optional target or delete them, and list the manual ones
in `agents/quick-start.md`; reword the gate comments in
`.github/workflows/check.yml`; prefix the multi-command recipes at
`Makefile:285-289,448-453,489-494` and `include/Makefile:13-29` with
`set -e;`; extend the `build`, `agent-pr-check`, `sanity-check`,
`stage-3`, `doc-examples`, `precommit`, and `verify` help lines and
`building.md:55-60` to name the tracked files they rewrite; fix the
`.gitignore:91` target name, the `FORMAT = 6` comment, and the
`RawDescriptionHelpFormatter` on `gate-state.py` and `agent-failure.py`;
correct `etc/release/README.md` (`main` ref, historical passages, the
0.15.0 date); refresh `tools/x2c-script-ports.md`; drop the duplicate
`agents/README.md` load from `.claude/settings.json` or `CLAUDE.md`.

**R28. Count runtime modules the way the catalog does (E-1).** Owner:
`tools/check-docs:270-279`. Count `lib/<m>/<m>.x` entries and exclude
generated `linked-meta`; then update `agents/x2c-docs-drift-report.md`
to describe the real link scope, the llms check, and the audited files.

### Batch 4. Tests and fixtures (focused suites)

**R29. Test hygiene (record C).** `unittest/test-lisp.x`: use
`Path.temp_dir()` and remove it in `finally` as `test-process.x` does.
`unittest/STATUS.md:69-76`: rewrite the REPL bullets against
`native-check.x`, `playground.py`, and `terminal.py`.
`macro-array-sequence.phases`: drop `cc-stderr` and delete the empty file.
`comptime-lowering.x`: rewrite the six compile-time-Lisp comments for
native meta execution. Update the seven `plans/meta-functions.md` paths and
`run-header-cache.sh:4`. Delete `unittest/probes/bound-template-expression.c`
and `unittest/probes/fixtures/macro-file-scope/`, or wire them to a
target. Guard the two empty-array expansions in
`unittest/compiler-fixtures/run.sh:226` and
`unittest/probes/run-full-sanitizer.sh:70`. Add the `definitions` phase to
`unittest/compiler-fixtures/README.md` and one sentence to
`unittest/AGENTS.md` saying a new probe is either wired to a target or
labelled optional in its header.

**R30. Coverage for this month's changes.** Add: a Channel test that
closes a full `Channel.new(1)` while a sender blocks and expects a join
failure; a Scope test that creates and destroys named and unnamed Scopes
from several threads; a `copy.capacity` assertion after copying a large
Map in `test-map.x`; the lint macro-prefix fixture (R18); the typed-list
`find` assertion (R8). No new target.

### Batch 5. Book, site, and release notes (doc-check, plus doc-outputs where samples change)

**R31. Release notes and upgrade steps (D-1).** Owner:
`docs/src/reference/release-notes.md` Unreleased and
`docs/src/guide/installation.md`. Add entries for the find/index break with
its migration table (move the prose from `collections.md:986-990`), the
`$switch` removal, `--cpp` becoming opt-in, the native playground and
`x2c repl` leaving installations, `x2c lsp` replacing `editor`, `x2c test`,
and the new runtime modules; add the Q7 signature changes once confirmed.
Quote the current rejection message for `$(import ...)` or link the
reference. Fix the `match` sentence to "most patterns". Replace the
interpreter-era REPL entries with one playground entry. Add "Upgrading
from 0.15.x" to the installation chapter.

**R32. REPL passages and links (D-2).** Fix the three fragments
(`release-notes.md:75,81`, `meta-functions.md:723`). Rewrite
`meta-functions.md:465-467,718-726` for native submissions that reject
`meta` declarations. In `language.md:2686-2687,4793-4794,4908-4909`,
`library/overview.md:262-263`, `architecture.md:707-708`, `macros.md:639`,
`index.md:47`, name the Lisp shell example or drop "the REPL". Align
`SUMMARY.md:32` with the chapter title and state checkout-only
availability. Correct the `:load` description and the `--package-dir`
command list in `cli.md:727-730`.

**R33. Public site (D-3).** Rewrite `site/src/content/home.md:19,40-41`
(real iterables; meta functions at compile time, `Lisp` at run time) and
`magic.md:11-13`; set `site/public/x2c-version.txt` and the package index
header to 0.15.1 or label them placeholders per `site/README.md:43-45`;
delete the inert `slide: runtime-lisp` line; apply Q6.

**R34. Internals and reference (D-4).** `architecture.md:256-257,264-268,
320-323` and `src/cpp/README.md:26-27`: describe `interface 8`, its six
fields, directive events, recomputed exports, and the full replay
condition set. `implementation-map.md:160,176-188`: name `splice.x`,
`walk.x`, `bindings.x`, the current key helper, and drop the deleted
fixture clause. `syntax/grammar.md:39-46`: copy the path rule from
`language.md:113-116` and name `splice.x`. Add `~=` to
`etc/syntax/lexical.x` and `etc/syntax/grammar.x`, regenerate, and add it
to the syntax-map row; change "eleven" to the table count. Apply Q5 to
`storage-ownership.md` and `channels.md:121`. Correct
`contexts-and-threads.md:12-14` and `library/overview.md:155-156` to the
shared-pool, non-isolated Context. Fix `networking.md` (`stop` vs `serve`
defers, `header` sets, `files` registers last, drop or narrow the TLS
sentence), `overview.md:361-362`, the missing Channel section,
`testing.md:62-63`, `cli.md:139-141,712`, `README.md:72-73`,
`packages.md:227` comment and `:221` `using` spelling (also
`unittest/probes/packages/tally/src/tally-defs.x`), `system-macros.md:18`,
`language.md:2232`, and the five SUMMARY labels.

**R35. Examples and packages text (D-5).** Replace "checked separately"
in `packages/AGENTS.md:24-26,191-193`, `packages/README.md:26,33-34`,
`examples/packages/README.md:56-58`, `docs/src/guide/packages.md:415`.
Correct `examples/README.md:237-240` (autodiff runs through
`packages/autodiff`). Fix the five file headers. Delete `.gitignore:52-53`.
Rewrite `http-json-releases/README.md:18` and note the network use.
Correct or remove the line counts. Show `auto` in the SQLite README and
guide. Drop the redundant `lib/substring*.x` arguments in
`examples/c2x2c/README.md:92-104` after one build of the stage. Catch
`<malformed>` around `Regex.compile` in `notes.x:106` and
`bench/threaded-notes.x:119` and fail with 400 "invalid search pattern";
pass `--store` under the app directory in `examples/apps/notes/Makefile:23-24`.

### Batch 6. Agent guidance and plans (doc-check)

**R36. Guidance (E-1).** `agents/x2c-code-standard.md`: delete the LI-1
rejection clause and the `:1328` row; drop `$refusal`/`$decline` from DG-1;
replace `component-*.x` and the flat module names in AR-1 and `:1304`;
extend MO-3 and the procedures list with module-member splits and the
`proposed-module-layout` skill; drop "and the REPL" from LI-1.
`agents/logger-and-diagnostics-guide.md:44-45,221-224`: remove the deleted
macros and cite `grouped-unquote-missing`, `grouped-unquote-mismatched`,
`grouped-list-splice-empty`. `agents/x2c-development-guide.md:39-41,80,92`:
scope the convergence sentence to local testing, describe `--cpp`, qualify
the system-header claim. Root `AGENTS.md:133-134,181-182,188-189`: list
`preprocess` and optional `cpp` as compiler modules, describe the native
playground, use one name for the Lisp assets. Skills: replace
`src/*.x lib/*.x` with `tools/sources.sh` lists in
`find-redundant-validation`, `clean-x2c-source`, and the beautify coverage
probe, and add `operator-ledger.o` there. `agents/x2c-debugging-guide.md:13,
159-161`: cite `src/macros/templates.x` and replace the stash recipe with a
WIP commit or a separate worktree. `agents/x2c-philosophy.md:85,119,120,605`:
name the member files and current functions. `agents/x2c-coding-style-guide.md:
248,855,864,882`: use a catalogue macro and a real API. Add `aliases.x` to
`src/macros/README.md` and `conditions.x` to `src/transform/README.md`; add
the seven runtime modules to `agents/x2c-code-organization-guide.md`. Align
`agents/README.md:64` and the release skill's `openai.yaml` with the
frontmatter. Correct `etc/vsc-extension/CHANGELOG.md`'s "experimental".

**R37. Plans (E-2).** Add the ten missing plans and the 10-26 archive to
`plans/README.md`. Archive `cpp-compatibility-boundary.md`,
`runtime-lock-mitigation.md`, `shared-root-index.md`, `notes-rewrite.md`,
and `notes-accounting-and-database-thread.md` as done with their delivery
revisions (PRs #641, #631, #628, #608, and 8abe19fad's batch). Archive
`c-preprocessor.md` as superseded by the boundary plan, noting the
never-implemented literal exclusion. Apply Q8 to the notes plan. Add one
sentence to `examples/apps/notes/bench/reports/2026-10-29-root-index/README.md`
saying both binaries linked an unshipped name-free Scope object and
pointing to the 10-29 runtime-locks repeat.

## Implementation order and delivery

1. Q1 to Q8 are settled. Batches 1 and 2 started on 2026-10-30 as an
   orchestrated set of workers in isolated worktrees from `ae3739230`.
2. Batch 1 and R9 share one authored compiler change and one full gate.
   Probe R10 before touching it. Run the existing performance checkpoint
   only if the `--cpp` default path changes; R1 to R5 do not touch it.
3. Batches 2, 3, and 4 are independent of batch 1 and of each other. Each
   keeps its focused checks: `commands-check` and the command scripts, the
   `tools/test-*.py` suites, and the affected unit suites.
4. Batches 5 and 6 are documentation. Land them after batches 1 and 2 so
   the text describes the repaired behavior, and regenerate the syntax
   data, API pages, and llms files through their owners.
5. Review the complete authored diff of each batch before its publication
   validation and fix what the review finds.

These are coherent work groups, not one commit or PR per finding. Delivery
follows the root instructions and the mode Gary selects: direct publication
by default, with `tools/gate-state.py ensure agent-pr-check` for a code
batch and `ensure doc-check` for a documentation-only batch. Record each
batch's revision here as it lands, and archive this plan with the last.

## Validation

- Batch 1: the new and extended `--cpp` fixtures, the header-cache probe,
  the runtime suites for array, map, net, http, typed-list, then the full
  gate on the integrated tree.
- Batch 2: `make commands-check`, the new `terminal.py`, `program.sh`,
  `features.py`, and lint cases, and a lint census that returns to zero.
- Batch 3: `tools/test-gate-state.py`, `tools/test-integrate-dev.py`, a
  `land-dev` test with a nested header, and the `git restore` acceptance
  for R24.
- Batch 4: the affected suites and probe scripts under `make verify`.
- Batches 5 and 6: `tools/gate-state.py ensure doc-check`, plus
  `make doc-outputs` where a checked sample changed.
