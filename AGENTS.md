# Repository Guidelines

x2c is a self-hosting superset of C that compiles to C. The compiler
(`src/`) and runtime (`lib/`) are written in x2c itself, so most changes
are judged twice: does the code work, and is it a worthy example of the
language?

## Project Priorities

The requested outcome and the beauty of the resulting code outrank what an
agent finds easy to measure. Beautiful x2c code is brief, direct, easy to
reason about, and sophisticated through composition rather than machinery.

- Prefer deleting code, reusing an existing path, or sharing an implementation
  before adding another representation, helper, layer, or special case.
- ASTs are the shared language of the parser, macros, compile-time Lisp,
  Match, transforms, and the C backend. Match and literal templates perform
  structural work; ordinary compiler operations own binding, typing, scope,
  lifecycle, placement, diagnostics, and emission order. Parsed and
  constructed syntax should enter those same operations, not parallel paths.
- Tests, validators, fixtures, artifacts, and process are evidence that the
  work is correct. They are not the result, and adding them is not progress by
  itself.
- Follow connected simplifications across files when they are part of the
  requested behavior. Stop for an unrequested change to public compatibility
  or semantics, not merely because the cleanup crosses modules.

Every implementation plan, regardless of author or interface, must be
scrutinized before it is presented for approval. Apply the validation rule
under Hard Rules to proposed code, not only to code already written, and end
the plan with the short design review required by `plans/README.md`. Revise a
plan that mistrusts an established producer, adds machinery for an earlier or
more specific failure, misses a deletion or reuse opportunity, or does not
describe idiomatic x2c. The plan's last implementation step must review and
fix the completed authored diff for those same problems before publication
proof.

## Communication

Gary does not need a session recap, but he does need the reasoning that makes
the conclusion understandable. He wrote x2c and its predecessors.

Answer the actual question in the first sentence. State what happened before
explaining what did not happen; do not begin with a rejected explanation and
make him read to the end to learn the answer.

Give enough concrete context to make the answer self-contained: name the
subject, cause, consequence, and next action when they matter. A short reply
that forces Gary to ask what its nouns refer to, why the result follows, or
what you plan to do has failed. Causes, mechanisms, measurements, file
references, and reasons are not disposable detail when they make the answer
intelligible.

At the end of a session or batch, report the current state, not the session
history. Lead with whether the requested work is done, whether the workspace
is safe to delete, and what Gary should do next; check the worktree and remote
publication state before saying it is safe. If work remains, name the concrete
next action. If you cannot continue, state the exact question or need. Do not
recap incidental problems, failed attempts, temporary blockers, or
intermediate decisions that no longer affect the result or Gary's next
decision.

Default to brief, normal prose, usually one or two paragraphs. Use headings,
lists, or tables only when they make a real comparison easier to follow. Cut
chronology, repeated evidence, process narration, and Git bookkeeping before
cutting the explanation. Put supporting detail in the pull request body, a
plan, or `.context/` when the reply remains understandable without it. Never
send Gary to another document for the status, remaining work, reason,
recommendation, decision, question, or other detail the summary owes him.

Bad news gets ordinary verbs: "I did not implement it", "I was wrong", "I did
not run that test", "the test fails". Never replace one of those with an
abstract technical condition. Use names already in the code or documentation;
do not invent categories, phases, schemas, or contracts to explain the work.
Words used in these instructions, including "owner", "boundary", and "proof",
are working language for agents, not vocabulary for Gary. Do not cite a
project rule from memory: give the file and rule, or say it is your own
recommendation. If he calls an explanation confusing, drop the disputed words
and start again from the concrete result; do not defend or rearrange it.

## Find What You Need

Always read the nearest `AGENTS.md`, any plan or specification named by the
user, and the source and tests that currently implement the behavior. Then use
the smallest matching project skill:

- `plan-x2c-change` to decide a design; `execute-x2c-plan` to carry out a
  decided feature, integration, example, or documentation change.
- `fix-x2c-bug` for a defect, including one inherited from a review finding.
- `integrate-x2c-package` for third-party C library work under `packages/`,
  including judging whether an existing package is complete.
- `review-x2c-repo` for a post-merge or whole-repository sanity check, or a
  focused pass over tests, benchmarks, documentation, or examples.
- `find-redundant-validation` for a read-only queue of over-validation
  candidates; `simplify-x2c-source` for an authorized campaign to remove the
  connected machinery; `clean-x2c-source` for local source cleanup after the
  structure is settled.
- `improve-x2c-agent-process` only for a dedicated review of the agent harness.

`agents/README.md` routes to deeper references. Use only the relevant section
of `agents/x2c-philosophy.md`, and consult the style or development references
when the task needs them. `docs/` owns language and library semantics; link to
it instead of restating those semantics in `agents/`.

Fan out subagents for discovery; it is cheap, and the sessions that ship most
are the ones that use it. Reproduce whatever one of them reports before you act
on it or repeat it to Gary, because they arrive confident and wrong often
enough to have cost graded work on premises that were false.

## Repo Map

- `src/` - the compiler, 27 modules: `main` (dispatch) -> `cli` (CLI) ->
  `compiler` (translation state) -> shared runtime `lib/tokenizer.x` ->
  `parse`/`expressions`/`statements`/`macros`/
  `literals` -> `ast` -> `type`/`protocol` -> `transform` (+ `lambda`) ->
  `generate`/`cache` -> `emit` -> `format`, with `diagnostics`, `snapshot`,
  `collect`, and `deps` in support; `project` lowers manifests to the same
  typed request that `build` owns, `toolchain` owns native actions,
  `report` owns progress and receipts, `bootstrap` owns the APE-to-native
  transition, and `utils` owns child execution.
- `lib/` - representative runtime modules include string, list, array, map,
  var, varconvert, varops, iter, match, scope, block, buffer, error,
  exception, file, logger, scan, tokenizer, symbol, symbolset, atom, pool,
  func, lisp, context, thread, mutex, dispatch, common, and `lib.x`
  (`DisjointSet`);
  `lib/x2c.x` is generated by the Makefile - never edit it.
- `bootstrap/` + `bin/` - the bootstrap chain. Never hand-edit `bootstrap/`;
  change `.x` sources and regenerate it with `make bootstrap-refresh`. A green
  stress test before regeneration is the normal safe sequence.
- `builds/` - staged toolchains (`builds/0` drives local builds).
- `agents/` - agent-facing documentation and project skills (`agents/skills/`,
  surfaced through `.agents/skills` for Codex and `.claude/skills` for Claude
  Code).
- `docs/` - the user-facing book (mdBook); `make doc-build` renders it.
- `unittest/`, `examples/`, `plans/`; `etc/` holds build tooling, the
  external Lisp bootstrap, and the compile-time Lisp SDK.
- `packages/` - optional adapters for third-party C libraries; they need
  network-fetched sources and are outside `make check`.
- `site/` - the public website; `make site-build` renders it with the book
  under `/docs/`. It is not gated.

## Build & Test

- Fresh checkout: `mkdir -p debug && make build-safe >debug/bootstrap.log 2>&1`.
  This rebuilds the bootstrap compiler and stage 0; later stages are built by
  `make stage-3`.
- After pulling or rebasing commits that change `bootstrap/`, run the same
  `make build-safe` command before using `builds/0` or running broad gates. A
  pre-existing stage 0 is not evidence that it matches newly pulled bootstrap
  sources.
- Batch coherent work before running broad gates. For ordinary compiler or
  runtime work that does not change the language accepted by the bootstrap,
  run `make build`, `make verify`, and `make stage-3` once on the integrated
  result, not after every edit, task, phase, or epic. Use a focused command
  during implementation only when it answers an immediate question.
- Green evidence belongs to the exact relevant tree. Run
  `tools/gate-state.py ensure <gate>` to reuse a valid result or run and record
  the gate when its result is stale or absent.
- If final validation fails, isolate the responsible part with focused checks
  or by testing progressively smaller halves of the batch. Do not pre-pay that
  cost by repeatedly validating every intermediate state.
- Language or bootstrap transitions are the exception: when new source syntax
  cannot be consumed by the checked-in bootstrap, stage the transition and
  validate at the explicit compatibility boundaries.
- `make verify-fixtures` checks exact compiler-boundary artifacts. Use
  `make verify-fixtures-update` only when intentionally accepting reviewed
  compiler output changes.
- `make sym-check` verifies the deterministic compiler symbol
  artifact. Use `make sym-update` only when intentionally
  accepting a reviewed symbol change.
- `make sym-refresh` refreshes the artifact, verifies deterministic
  regeneration, and displays its diff.
- `make proof-conformance` proves owned protocol conformances agree between
  snapshot and live symbol modes; `x2c translate --dump-conformance <units>`
  prints the per-unit conformance table it compares. It is an optional focused
  command, not part of symbol refresh or publication checks.
- `make check` is the extended non-mutating integration suite.
- `make precommit` checks the symbol snapshot, refreshes header symbols,
  refreshes bootstrap, performs a safe build, builds through stage 2,
  and compares stages 0, 1, and 2. Stage 2 is where the compiler reproduces
  its own output, so the fourth round adds nothing; `make stage-3` and
  `make stage-diff-all` still run it on demand. Its agent publication
  requirement is below; do not add other checks to this target.
- `tools/gate-state.py ensure agent-pr-check` is the complete code-publication
  command for agents. When needed, it runs the existing `agent-pr-check`
  target: `make precommit`, then the parts of `make check` that precommit did
  not already prove, including the header-symbol check.
- `make sanity-check` is Gary's personal recovery sequence: refresh bootstrap
  from the current compiler, rebuild stage 0 from that bootstrap, then build
  through stage 3. It intentionally runs no check target or stage comparison.
- `make artifact-refresh` rewrites the symbol artifacts and bootstrap from
  current source. It is not publication proof by itself.
- `make examples` checks the curated examples manifest. Use
  `make examples-update` only when intentionally accepting reviewed showcase
  output changes.
- `make packages-check` tests every package under `packages/`, the two
  accepted ones and the five still awaiting review. It is optional and is
  deliberately outside `check`, `precommit`, and `agent-pr-check`, because it
  needs a prepared dependency cache. Run it after a compiler or runtime change
  that could reach a package client.
- After a green stress test, `make stage-diff-all` compares only the
  generated C/H file sets and bytes.
- During development, `make stage-3` before an explicit bootstrap refresh can
  show that the C being copied came from a converged stage. For publication,
  `tools/gate-state.py ensure agent-pr-check` owns reuse or execution of the
  final validation sequence; do not add a separate broad build unless the task
  is an explicit staged language transition.
- A change to `src/` or `lib/` leaves `stage-diff-0` red until you refresh the
  bootstrap, since
  it compares the checked-in `bootstrap/` snapshot against stage 0. Refreshing
  the snapshot moves that generated-C delta out of a failing gate and into the
  commit, where it is reviewed like any other diff. Read it before committing;
  it should contain nothing you cannot trace to your source change.
- Save complete stdout and stderr from a failure under `debug/`.
- Ad-hoc sample: `mkdir -p /tmp/x2c-example && ./builds/0/x2c translate --out-dir
  /tmp/x2c-example examples/foreach.x`; compile the generated
  `/tmp/x2c-example/foreach.c` against `builds/0/libx2c.a`.

## Bootstrap Publication

- Agents may run `make bootstrap-refresh` and `make artifact-refresh` when
  relevant to the authorized task.
- Source changes may be committed without refreshing `bootstrap/` while work
  is in progress. Agent publication follows the requirements below.
- If the outgoing commit range changes `bootstrap/`, do not push until
  `tools/gate-state.py ensure agent-pr-check` succeeds on the exact final tree.
  The target it runs owns the bootstrap refresh, safe rebuild, and fixed-point
  comparison; do not add a separate `make stage-3` unless the task is an
  explicit staged language transition.
- A later tracked source, artifact, or bootstrap edit invalidates that
  publication evidence. Ensure the applicable gate again on the new final tree.
- If the proof fails, preserve the changes and complete failure log, stop
  before push, and report the failing command. Never patch generated
  bootstrap files to make the proof pass.
- Publishing to a feature branch or `main` follows ordinary task
  authorization. The repository has no additional human-only branch rule.

## Agent PR and Merge Requirements

- Before an agent pushes code for a PR, opens or updates a code PR, or merges
  code into `main`, run `tools/gate-state.py ensure agent-pr-check` on the
  resulting final tree. It reuses valid evidence or runs the existing
  `agent-pr-check` target, which performs `precommit` and the extended checks
  without rebuilding the self-hosting stages twice.
- This applies when the outgoing changes include source, runtime, build, test,
  tool, executable-example, or generated-artifact files. A later tracked edit,
  artifact refresh, rebase, or merge that changes that tree invalidates both
  parts of the result. A commit, review, push, or PR action does not.
- Do not separately run `make precommit`, `make check`, `make build-safe`,
  `make stage-3`, `make stresstest`, or `make stage-diff-all` merely because
  publication was requested; `tools/gate-state.py ensure agent-pr-check`
  already reuses or performs the required work. Focused commands used earlier
  remain appropriate.
- A documentation-only change instead requires
  `tools/gate-state.py ensure doc-check`. It does not require
  `agent-pr-check` unless it also changes executable examples, build or test
  tooling, or generated artifacts.
- If a required command fails, preserve the changes and complete failure log,
  stop before push or merge, and report the failing command.

## Agent PR Push

- For a PR, `main` is the base branch, not the push destination. Push the
  current workspace branch to the same-named remote branch with an explicit
  refspec:

  ```sh
  branch="$(git branch --show-current)"
  git push -u origin "HEAD:refs/heads/$branch"
  gh pr create --draft --base main --head "$branch"
  gh pr view --json baseRefName --jq .baseRefName   # must print main
  ```

- Never base a PR on another workspace branch. A squash merge of that base
  replaces its history, so the stacked PR reports merged while its change never
  reaches `main`. When two branches change the same files, rebase onto `main`
  and resolve the conflict, or wait
  for the other to land. The base check above is the whole guard: a content
  comparison after the merge is not, because later commits legitimately touch
  the same files.
- Do not use a source-only push such as `git push`, `git push origin <branch>`,
  or `git push -u origin <branch>` for PR publication. A workspace branch may
  still track `origin/main`, causing those commands to update `main`.
- Publishing directly to `main` requires separate explicit authorization.

## Process Ceiling

- `make precommit` is Gary's personal PR-readiness definition. The publication
  rule above requires agents to run it for code, but does not authorize
  changing what it does. Do not fuck with it unless the change makes it faster
  or simpler, or is required for actual build correctness.
- `make sanity-check` remains the three-build recovery sequence above. Do not
  add checks to it or turn it into another publication requirement.
- `make agent-pr-check` only consolidates the existing agent publication
  proof. Do not add checks to it unless an existing requirement of comparable
  cost is removed or consolidated.
- Only Gary may approve adding, expanding, or reordering process that increases
  build time or `make precommit` time. Approval must be explicit and obtained
  before making the change. More coverage, consistency, documentation drift,
  or general caution are not sufficient reasons.
- The project's process and bureaucracy are at their maximum. Do not add a
  mandatory gate, test, artifact check, planning step, commit step, or other
  recurring requirement without Gary's explicit approval. Any proposal for
  more process must identify an existing step of comparable cost to remove or
  consolidate.
- Keep other optional checks optional and out of `make precommit`.

## Testing Contract

- Suites are `unittest/test-<feature>.x`; tests are `static void`
  functions registered with `$test.run`, or with an explicit
  `TestHarness_run` when the label is not the function name, inside a
  `void <name>_suite(void)` wired into `test-all.x`.
- Call `EXPECT_*` macros as bare statements. The harness is the pass/fail
  authority: a test fails on a failed assertion, zero assertions, or extra
  pushed/retained scope state. Ambient errors remain with their configured
  policy owner. Deferred tests use explicit skips. Never thread `ok` flags or
  return pass/fail. Details: `unittest/AGENTS.md`.
- Compiler fixtures are under `unittest/compiler-fixtures/`. Ordinary test
  commands never rewrite their checked-in expectations.

## Style & Commits

- 2-space indent, 79-character lines, never `} else`; exported helpers are
  `Struct.method`, private helpers `_snake_case`. Full rules in the style
  guide.
- Commit subjects: short, lower-case, present tense (`fix symbol caching`);
  update docs when behavior changes.
- Before committing, inspect tracked and untracked changes, run
  `git diff --check`, and confirm no temporary or generated build output is in
  the diff.

## Hard Rules

- Compile-time Lisp may construct and return any canonical AST List. The
  compiler deliberately does not authenticate whether a legal AST shape came
  from the parser, a Match capture, a template, or handwritten Lisp; the
  language rule is recorded under "Macro-visible syntax" in
  `docs/src/reference/language.md`. Do not report accepted `src`,
  `construct(src)`, static declarations, or other canonical shapes as
  forgery. Do not add origin markers, producer-identity registries, secondary
  validators, repair walks, or negative fixtures to reject them. Ordinary
  operations still reject malformed data and forms they cannot consume at
  that position. This unsafe metaprogramming risk is intentional, like C's
  bad-pointer risk, and is not an open defect.
- Do not add a check solely to make invalid source fail earlier or with a
  custom diagnostic. If the existing parse, type, generation, native compile,
  or runtime path rejects it without accepting wrong output, corrupting state,
  or crossing an unsafe native boundary, use that failure. Add a dedicated
  validator and negative fixture only when they enforce deliberate public
  behavior or prevent one of those concrete failures.
- Every shared Error cause listed in `lib/error-macros.xmacro` never returns
  to the raising call. Such a cause may transfer to a matching `catch`;
  otherwise it terminates. Do not attach `$error.fallback` to one, check a
  fresh `%[]` or `%{}` for null, or check whether a valid allocation, growth,
  open, read, write, format, or binding call succeeded. Keep checks for
  documented null inputs, absence, callbacks, and other failures that can
  still return, and keep `$error.fallback` for user-defined causes.
- Never hand-edit `bootstrap/`, and never broaden public semantics without
  approval. `make bootstrap-refresh` and the documented artifact targets are
  the only ways to change `bootstrap/`, which keeps the checked-in generated C
  traceable to the `.x` sources it claims to come from.
- Temporary outputs go in `/tmp` or `unittest/build/` and are never
  committed. Keep new files ASCII.
- Respect existing dirt in the worktree; never revert user edits.
- No debug prints or scaffolding in shipped code; diagnostics go to
  `debug/*.log`.
- Stop and escalate when build/test failures increase, the required design is
  unclear, or the work would change public compatibility or semantics beyond
  the request. Connected work may span modules when the requested result needs
  it. Network actions require task authorization; an authorized push is
  allowed subject to the Bootstrap Publication rule.
  Documented build and artifact targets may rebuild derived files; direct
  destructive commands and hand-written bootstrap edits still require
  approval.
- Review requests are read-only: do not modify the worktree unless the
  user explicitly authorizes it for that session.
