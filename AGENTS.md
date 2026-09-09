# Repository Guidelines

x2c is a shipped, self-hosting superset of C maintained on `main`. The
compiler (`src/`) and runtime (`lib/`) are working examples of the language.
Make each requested change useful, idiomatic, and verified, moving the
repository from one healthy state to the next.

## Start with the task

Read the nearest `AGENTS.md`, any plan or specification the user named, and
the source and tests that implement the behavior. Use
[agents/README.md](agents/README.md) to select the smallest matching skill
and relevant references; it is the task directory for this repository.

Begin with a working example of the same kind of code. The
[idioms chapter](docs/src/guide/idioms.md) explains language choices;
`examples/manifest.txt` identifies executable examples and their checks.
Current source and tests establish implementation behavior. The book under
`docs/` owns language and library semantics; agent guidance links to it.

An implementation request authorizes routine implementation decisions,
verification, and delivery as described below. A request for investigation,
review, advice, or a plan is read-only unless it also authorizes changes.
Resolve consequential choices with Gary when the request leaves them open,
especially changes to public semantics, compatibility, or caller obligations.
Complete routine missing plan details and its design review within an
already authorized implementation; a missing heading is not a reason to stop.

Use subagents for independent discovery or bounded work. Verify a reported
finding against current source and reproduce claimed behavior before acting
on it or presenting it as established.

## Write x2c that belongs here

Prefer composing current language features and existing operations. Follow a
connected simplification across files when it serves the requested behavior.
Beautiful x2c is brief, direct, and easy to reason about; measurements and
passing tests support that result rather than replace it.

- Match and literal templates express AST structure. Reuse ordinary compiler
  operations for binding, typing, scope, lifecycle, placement, diagnostics,
  and emission order. For compiler syntax work, read
  `agents/replacing-manual-ast-walks-with-match.md`.
- Compile-time Lisp may construct any canonical AST List. Ordinary operations
  accept forms by structure and position, without authenticating their origin.
  Preserve this deliberate behavior described under "Macro-visible syntax"
  in `docs/src/reference/language.md`; do not add origin tracking or a second
  validator to reject legal constructed syntax.
- Trust facts established by the producing operation. Add validation or a
  dedicated diagnostic only to preserve deliberate public behavior or prevent
  wrong output, corrupted state, or an unsafe native crossing. Earlier or
  more specific rejection alone does not justify another check or fixture.
- Every shared Error cause in `lib/error-macros.xmacro` transfers to a matching
  catch or terminates; it never returns to the raising call. Rely on that
  behavior after valid allocation, growth, open, read, write, format, and
  binding operations. Keep checks for documented null inputs, absence,
  callbacks, and other returning failures; reserve `$error.fallback` for
  user-defined causes. Fresh `%[]` and `%{}` need no null checks.
- Choose representations and scopes by their actual identity and lifetime
  behavior. Consult the relevant section of `agents/x2c-philosophy.md` for
  technical facts and their evidence.
- Follow `agents/x2c-coding-style-guide.md`: 2-space indentation, 79 columns,
  separate `else`, exported `Struct.method` operations, private `_snake_case`
  helpers. Update the book when documented behavior changes.

Review a design before implementation and the completed authored diff before
publication validation. Look for existing code to reuse or delete, checks
that repeat established facts, and new machinery that does not earn its keep.
Fix what the review finds. Durable plans follow `plans/README.md`.

## Work in the repository

Preserve unrelated work and inspect tracked and untracked changes before
committing. Edit authoritative sources; use documented targets to regenerate
`bootstrap/`, `lib/x2c.x`, symbol artifacts, and generated documentation.
Never hand-edit bootstrap C/H. Keep temporary outputs in `/tmp` or
`unittest/build/`, workspace notes in `.context/`, and full failure logs in
`debug/`. Keep new files ASCII and shipped code free of debug scaffolding.
Direct destructive operations outside the requested change need approval.

## Repo Map

- `src/` - the compiler: `main` (dispatch) -> `cli` (CLI) ->
  `frontend` (configured source units) -> `compiler` (translation state) ->
  shared runtime `lib/tokenizer.x` ->
  `parse`/`expressions`/`statements`/`macros`/
  `literals` -> `ast` -> `type`/`protocol` -> `transform` (+ `lambda`) ->
  `generate`/`cache` -> `emit` -> `format`, with `diagnostics`, `snapshot`,
  `collect`, `deps`, and `sourceview` in support; `project` lowers manifests
  to the same typed request that `build` owns, `toolchain` owns native actions,
  `report` owns progress and receipts, `bootstrap` owns the APE-to-native
  transition, and `utils` owns child execution.
- `lib/` - representative runtime modules include string, list, array, map,
  var, varconvert, varops, iter, match, scope, block, buffer, error,
  exception, file, logger, scan, tokenizer, symbol, symbolset, atom, pool,
  func, lisp, context, thread, mutex, dispatch, common, and `lib.x`
  (`DisjointSet`);
  `lib/x2c.x` is generated by the Makefile - never edit it.
- `bootstrap/` + `bin/` - the bootstrap chain. Never hand-edit `bootstrap/`;
  change `.x` sources and regenerate through the publication command below.
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

## Verify and deliver

Use `agents/quick-start.md` for setup, focused commands, and optional checks.
Reproduce a reported defect before editing and verify the user-visible result
with the relevant tests or executable examples. Unit suites and compiler
fixtures follow `unittest/AGENTS.md`; ordinary checks preserve checked-in
expectations. Batch coherent work before broad validation.

Fresh worktrees, or worktrees that have integrated changed `bootstrap/`, need
`mkdir -p debug && make build-safe >debug/bootstrap.log 2>&1` before using
`builds/0`. During implementation, build or probe when it answers a current
question. A language transition that the checked-in bootstrap cannot consume
needs explicit intermediate validation; ordinary publication uses the single
command below.

Before publishing, fetch and integrate current `origin/main`, review the
resulting diff and generated changes, and run `git diff --check`. Commit
subjects are short, lower-case, and present tense. Validate the final tree:

- Code, runtime, build, test, tool, executable-example, or generated-artifact
  changes: `tools/gate-state.py ensure agent-pr-check`.
- Documentation-only changes: `tools/gate-state.py ensure doc-check`.

The code command reuses valid evidence or runs `precommit` and the remaining
extended checks. It owns bootstrap refresh, safe rebuild, and self-host
comparison; do not run its broad components separately merely to publish.
Review every resulting artifact delta. Edits, regeneration, or integration
that change the validated tree require ensuring the command again. A commit,
review, push, or elapsed time does not invalidate an unchanged result.

A failed required check stops publication. Preserve the changes and full log,
isolate the cause with focused checks, and report the failing command when
work cannot continue within scope. Escalate an increase in failures or an
unresolved consequential design choice rather than hiding it in output.

Routine implementation includes validated delivery directly to `main` unless
Gary requests a PR, review stop, or local-only work. Network actions needed
for that delivery are authorized by the task. Use the explicit destination:

```sh
git push origin HEAD:refs/heads/main
```

If the push is rejected because `main` advanced, fetch, integrate, review,
and validate the new tree before retrying. Never force-push `main`.

For a requested PR, push the current workspace branch to the same-named
remote branch and use `main` as the base:

```sh
branch="$(git branch --show-current)"
git push -u origin "HEAD:refs/heads/$branch"
gh pr create --draft --base main --head "$branch"
gh pr view --json baseRefName --jq .baseRefName   # must print main
```

Keep a requested PR available for review unless merging is also requested.
Use `main` as the base even when another workspace has related changes.
Choose push destinations explicitly; the branch's upstream does not choose
where either form of delivery goes.

### Process ceiling

Preserve the existing validation targets. `precommit` is Gary's readiness
sequence; changes to it must make it faster or simpler, or be necessary for
build correctness. `sanity-check` remains bootstrap refresh, safe rebuild,
and builds through stage 3, without added checks. `agent-pr-check` consolidates
existing publication checks; additions require removing or consolidating an
existing requirement of comparable cost.

Gary's explicit approval is required before adding, expanding, or reordering
process that increases build or precommit time, or adding any recurring gate,
test requirement, planning step, or commit step. Proposals must identify
existing work of comparable cost to remove or consolidate. Keep optional
checks optional.

## Communicate the result

Answer the actual question in the first sentence. Use ordinary verbs for
mistakes, uncertainty, changed behavior, and failed tests. Name the subject,
cause, consequence, and next action when needed to make the answer clear.
Use existing project names and plain language; when an explanation confuses
Gary, restart from the concrete result.

Default to brief prose, with enough detail for the requested explanation.
Use lists, tables, or headings when they help. Report current results and
remaining work rather than session chronology; supporting detail can live in
the plan, PR, or `.context/`, but the answer must stand on its own. Identify
project rules by their current file or distinguish your own recommendation.

At completion, state what was delivered, what was verified, and any remaining
work. Check worktree and remote state before saying a workspace is safe to
delete. If blocked, name the exact failing command, missing decision, or
external change needed to continue.
