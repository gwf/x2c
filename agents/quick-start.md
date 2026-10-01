# X2C Quick Start

Use this page for current commands and repository orientation. The root
`AGENTS.md` owns workflow and publication rules.

Everyday integration and requested PR bases target `dev`; fetch and integrate
`origin/dev` before direct publication. `main` advances only through
Gary-authorized release promotion. Existing checkouts keep their work; use an
explicit `HEAD:refs/heads/dev` push destination rather than relying on an old
upstream.

## Choose delivery

An individual session normally integrates and publishes its own change.
`orchestrate-x2c-work` normally integrates and publishes its workers' combined
work. To use shared integration, Gary starts `integrate-x2c-prs` in a
persistent checkout and tells selected individual sessions or orchestrators to
use the integrator. Those sessions submit ready PRs; other sessions keep their
chosen mode. A running integrator is not a global switch.

Agents establish the selected worktree context, for example:

```sh
tools/integrate-dev.py context --role individual --delivery direct
tools/integrate-dev.py context --role individual --delivery pr
tools/integrate-dev.py context --role orchestrator --delivery pr
tools/integrate-dev.py context --role worker --delivery private
tools/integrate-dev.py context --role integrator --delivery direct
```

These are alternatives, not a sequence. The explicit session instruction
persists until changed. Set subordinate worker context in its actual worktree
before it starts. Worker handoffs stay private even when the parent uses PR
delivery. An independent working session uses `individual`; `worker` is only
for subordinate private handoffs. Context is ignored worktree-local state in
`debug/agent-context.json`; the common Git hook protects shared branches for
both providers. Setup checks the effective hook path and executable hook and
reports incompatible existing configuration instead of overwriting it.
Canonical instructions and skills are shared through the existing discovery
links.

### Submit to the shared integrator

Record the exact starting commit before editing, including a capability commit
when dependent work starts from one. Finish and review the authored change,
run the relevant focused checks, and commit it on a branch based on `dev` or
the recorded dependency revision. An orchestrator first collects and checks
its workers' private handoffs into one or more coherent changes.

Write its reviewed description in `.context/submission/pr-body.md`, then
create a ready, same-repository PR targeting `dev`:

```sh
branch="$(git branch --show-current)"
git push -u origin "HEAD:refs/heads/$branch"
gh pr create --base dev --head "$branch" \
  --body-file .context/submission/pr-body.md
```

Write a JSON list of focused-check commands and results, for example:

```json
[
  {"command": "git diff --check", "result": "passed"},
  {"command": "focused compiler fixture", "result": "passed; fixture NAME"}
]
```

Replace the example with the commands actually run. A result may explain why
no runtime check applies. Save it in `.context/submission/evidence.json`,
outside `unittest/build/`, which a gate clears. Enroll the PR with the
coordinator; the arguments below are
placeholders for the PR number, recorded full commit IDs, and evidence path:

```sh
tools/integrate-dev.py submit --pr N --base STARTING_SHA \
  --evidence-file .context/submission/evidence.json
```

Add `--depends-on N:HEAD_SHA` for each required PR revision and `--notes TEXT`
for bootstrap transition or interaction notes. The submitting checkout's
clean `HEAD` must match the PR head. The coordinator preserves PR prose,
writes the pinned submission metadata, and applies `integration-ready` last.
Re-run `submit` after changing the head; old metadata does not enroll a new
revision. Attach the PR in the app when supported, without making that feature
part of the common protocol.

This is a work submission. Do not run a full publication gate, merge a moving
`dev`, or refresh final artifacts solely to push it. Local development builds,
meaningful focused tests, and necessary intermediate bootstrap refreshes
remain available. The integrator owns the final combined review, generated
artifacts, gate, and `dev` push. Report the PR and focused evidence as
submitted; the integrator records actual publication. If it is absent, the
PR waits.

For a requested review stop, create a draft PR using normal publication
validation and leave it unenrolled. A PR alone is never automatic permission
to integrate. Local-only work stays local. Integration readiness requests
landing the pinned revision; removing it cancels only if observed before push.

Queue commands are agent responsibilities. The standing skill uses `status`,
`wait --timeout 60`, `prepare`, `land <batch-id>`, `land <batch-id> --publish`,
and `park <batch-id>`; Gary need only start the integrator and select it for
submitting sessions. Records and preserved candidates live under the
integration checkout's ignored `debug/integration/` directory and survive
session restarts.

## Build and validate

From a fresh worktree, or after integrating a changed `bootstrap/`:

```sh
mkdir -p debug
make build-safe >debug/bootstrap.log 2>&1
```

Use `make build` when a source change needs a current compiler. It rebuilds
stage 0, whose library batch writes the unit interfaces later translations
replay as the runtime prelude. Use a focused compiler
invocation or test to answer the question being worked on. The root
[Verify and deliver](../AGENTS.md#verify-and-deliver) section owns final
validation and publication; the commands below are a reference, not another
required sequence.

| Command | Purpose |
| --- | --- |
| `make build` | Rebuild the current development compiler. |
| `make bootstrap-refresh` | Regenerate the bootstrap with the current compiler. |
| `make build-safe` | Cleanly rebuild stage 0 from bootstrap. |
| `make stage-2` | Build through stage 2 for a local self-host experiment. |
| `make proof-raw-symbols` | Optional full-corpus symbol-mode comparison. |
| `make verify` | Unit suites, compiler fixtures, and focused probes. |
| `make stage-3` | Build through the third self-hosted stage. |
| `make stage-diff-all` | Compare generated C/H file sets and bytes across stages. |
| `make proof-cold-collection` | Compare stage 1 with a translation that reads no `.xi` interfaces. |
| `make check` | Standalone extended non-mutating checks. |
| `make verify-fixtures` | Check exact compiler fixture artifacts without rewriting them. |
| `make verify-fixtures-update` | Accept an intentional, reviewed fixture-output change. |
| `make proof-conformance` | Optional prelude/live protocol conformance comparison. |
| `make check-native-modules` | Optional native module build, load, and rejection checks. |
| `make examples` | Check the curated executable examples manifest. |
| `make examples-update` | Accept intentional, reviewed example-output changes. |
| `make doc-examples` | Compile the book's code examples; optional. |
| `make packages-check` | Check packages with their prepared dependency cache; outside `check`. |
| `make sanity-check` | Refresh bootstrap, rebuild stage 0, and build through stage 3 without checks. |
| `make build-recovery` | Check that an interrupted stage build removes partial objects and replaces archives. |
| `make performance-snapshot` | Record representative build, runtime, shootout, and compiler timings. |
| `python3 tools/test-configure.py` | Check `./configure` prerequisite reporting and its ordering before the core build. |

For an optional focused unit run, build with `make -C unittest test-all`, then
pass exact suite names, for example
`(cd unittest && ./test-all string_suite lambda_suite)`. Names come from
`unittest/test-all.x`. Selected suites keep their normal execution order;
duplicates run once and unknown names return status 2. Without arguments the
runner executes every suite, as the existing validation commands do.

For optional parallel stage translation, use
`make build X2C_FLAGS='-j 4'`. Native compilation retains its existing Make
job limit. On the measured 16-core host this reduced clean-stage wall time
29% with identical generated C/H and 3.8% more CPU time; the default remains
unchanged. The B4/B5 section of
`plans/archive/x2c-correctness-performance-tooling.md` records the full comparison.

Stages 1 and up translate `lib/` and `src/` with the hidden
`--fatal-warnings` option and compile the generated C with `-Werror`, so an
x2c warning, a region finding, or a C compiler warning fails `make stage-1`
and the gates built on it. Stage 0 stays lenient: the checked-in bootstrap
translates it, and source installs compile it with the host C compiler.
The option stays out of user builds and `unittest/`, whose suites provoke
region warnings on purpose.

Private worktree commits may be made whenever useful, with no checks required
merely to commit. For a language feature followed by adoption, build the
feature, refresh bootstrap when the seed needs that capability, and try its
callers locally. The build and stage commands above are available experiments,
not a required local sequence or a reason to publish the feature separately.

`make precommit` is a publication-readiness target, not a Git commit prerequisite.
It refreshes bootstrap, rebuilds stage 0 safely, builds through
stage 1, and compares stages 0 and 1. `agent-pr-check` runs it,
`doc-check`, `proof-cold-collection`, and the remaining extended checks.
The full `proof-raw-symbols` sweep remains an explicit optional command.
`stage-diff-0` establishes self-host convergence, and stage 1 adds the
warning-free build; later stages run on demand and in the nightly snapshot.
`proof-cold-collection` retranslates `lib/` and `src/` with stage 0 and the
hidden `--no-interfaces` option, then requires stage 1's C, headers, and
interfaces byte for byte, so warm interface replay cannot drift from a cold
walk.

Performance evidence is separate from these correctness gates. Use
[`performance-snapshot`](performance-checkpoints.md) for the nightly `dev`
history and for coherent authored batches that can affect compiler or runtime
performance.

Source changes can leave `stage-diff-0` red until bootstrap is regenerated:
it compares checked-in bootstrap C/H with stage 0 output. The publication
command owns the final refresh; inspect its generated diff. A local language
transition may refresh bootstrap earlier and use individual self-host stage
comparisons without running the publication gate.

Use `x2c translate --dump-conformance <units>` for a per-unit conformance
table. Run package checks when compiler or runtime changes can affect package
clients. Examples, book examples, and packages remain optional checks; choose
them for relevant work. Save full failure output under `debug/`.

Use `builds/0/x2c` for current development behavior. `bin/x2c` is the
bootstrap compiler unless stage 0 was intentionally installed.

## Compile an example

Build an ordinary native executable with the driver:

```sh
./builds/0/x2c build --output /tmp/foreach examples/foreach.x
/tmp/foreach
```

Use `translate` when another build owns native compilation:

```sh
mkdir -p /tmp/x2c-example
./builds/0/x2c translate --out-dir /tmp/x2c-example examples/foreach.x
cc -iquote include/x2c /tmp/x2c-example/foreach.c \
  builds/0/libx2c.a -lm -o /tmp/x2c-example/foreach
/tmp/x2c-example/foreach
```

Generated output keeps the input basename. `make examples` checks the curated
manifest, including the deterministic Lisp showcase.

## Repository map

- `src/` - compiler dispatch, CLI, translation, parsing, types, transforms,
  generation, native builds, project manifests, reporting, and support.
- `lib/` - runtime values, collections, iteration, matching, scopes, IO,
  scanning, tokenization, logging, dispatch, and generated `lib/x2c.x`.
- `bootstrap/` - generated portable C seed; never hand-edit it.
- `builds/0` - current development compiler and runtime archive.
- `builds/1` through `builds/3` - self-host stages built by `make stage-3`.
- `unittest/` - executable suites, compiler fixtures, and probes.
- `examples/` - curated executable examples.
- `docs/` - language, library, and compiler book.
- `agents/` - task routing and implementation references.
- `plans/` - active plans and archived decisions.
- `etc/` - shared build rules, Lisp bootstrap, and SDK.
- `packages/` - optional third-party adapters, outside `make check`.
- `site/` - public website; it is not gated. Candidate assembly retains complete destination sites; promotion deploys
  their version file and package index together; see [Releasing](releasing.md).

`agents/x2c-module-catalog.md` is generated from current source. Run
`make doc-check` to verify it.

## Implementation landmarks

- Percent literals and lambdas: `src/literals.x`.
- Statements: `src/statements.x`; the built-in `foreach(item, collection)`
  source macro: `etc/builtin-macros.xmacro` and `src/builtins.x`, loaded by
  `src/macros.x`.
- Type initialization: `src/parse.x`, `src/generate.x`, and `src/cache.x`.
- Type conversion: `src/type.x`, `src/expressions.x`, `src/transform.x`,
  `lib/varconvert.x`, and `lib/varops.x`.
- C token emission and formatting: `src/emit.x` and `src/format.x`.
- Native actions and project lowering: `src/toolchain.x`, `src/build.x`, and
  `src/project.x`.
- Shared scanning and tokenization: `lib/scan.x` and `lib/tokenizer.x`.

The book owns language semantics. Start with
`docs/src/reference/language.md`, `docs/src/guide/collections.md`, and
`docs/src/internals/implementation-map.md` instead of copying semantics into
agent guidance.
