# Build CLI defaults and examples

> Status: active
> Gary accepted the survey recommendations on 2026-10-21 and requested this
> implementation plan. Gary subsequently authorized implementation.
> Implementation is recorded in `c91d7ed43`. Focused checks and the complete
> CLI boundary probe pass. Gary authorized delivery despite the known stage-1
> warning. Exception validation passed, but the push raced with the upstream
> repair. That repair is now integrated; normal validation is pending.
> Planning baseline: `e2a78078edece1348abbbb7363c89560ae064706`.

## Result

Make ordinary translation, compilation, and execution commands short and
predictable. Explain existing defaults before introducing overrides. Remove
unnecessary directory setup, make retained builds reusable, and use the
compiler that matches each example's working directory and installation.

This plan includes all six accepted survey recommendations. It is one coherent
CLI and documentation change, not a new build system or a compiler refactor.
The original planning request stopped at this plan. Gary's subsequent request
authorizes implementation and delivery under the repository workflow.

## Current behavior and evidence

The survey inspected the CLI parser and help, native build driver, manifest
planning, book, README, examples, agent guidance, Makefile, and external build
rules. `make build-safe` succeeded in this worktree. Focused real invocations
and dry runs established the following behavior; the full suite was not run.

| Invocation or setting | Observed behavior |
| --- | --- |
| `./x2c translate hello.x` | Writes `.c`, `.h`, `.xi`, and `.d` into the working directory. |
| `./x2c build hello.x` | Writes `a.out` into the working directory. |
| `./x2c build -c hello.x` | Writes `hello.o` into the working directory. |
| Static library without `--output` | Uses `lib<first-input-stem>.a`. |
| `./x2c run hello.x` | Runs a private temporary executable. |
| Manifest build without a directory override | Plans artifacts under `<project>/.x2c-build/`. |
| `translate --out-dir absent hello.x` | Rejects a missing directory. |
| Native `build --output nested/app main.c` | Creates missing destination parents and succeeds. |
| Repeated `--save-temps=retained` native builds | Retains files but recompiles the source. |
| Repeated `--build-dir cached` native builds | Reuses the unchanged object. |
| Both named directory options | `--build-dir` wins even when `--save-temps=<dir>` comes later. |
| Manifest plus `--save-temps=<dir>` | Ignores that requested directory. |
| `build -c hello.x helper.c` | Requires `--build-dir`. |
| `build -o hello hello.x` | Rejects the deliberately removed spelling. |
| `build --build-dir= hello.x` | Treats the empty directory as omitted. |

Source owners:

- `src/cli/parsing.x`: option vocabulary, parsing, and empty values.
- `src/cli/help.x`: command descriptions and notes.
- `src/cli/requests.x`: job count and other request defaults.
- `src/translation.x`: default translation directory and preflight.
- `commands/build/build.x`: artifact names, intermediate directories, object
  destinations, reuse, compilation database entries, and cleanup.
- `src/project/planning.x`: manifest discovery, target selection, and paths.
- `unittest/probes/run-cli-boundary.sh`: existing CLI boundary coverage.

The book already states the translation default, but leads with directory
setup. Build help and the book omit native artifact naming defaults. Retention
and reuse are difficult to distinguish, and the manifest defaults are scattered.

## Decided behavior

### 1. Preserve sensible defaults and explain them

Keep these defaults:

| Operation | Product | Intermediate files |
| --- | --- | --- |
| Direct translation | Matching files in `.` | Translation products remain there. |
| Direct executable build | `./a.out` | Private temporary directory; removed after success. |
| Single-input compile-only build | `./<stem>.o` | Private temporary directory unless retained. |
| Direct static library | `./lib<first-input-stem>.a` | Same direct-build lifetime. |
| Direct meta module | `./<first-input-stem>.so` | Same direct-build lifetime. |
| Direct run | Executable in the work directory | Temporary unless retention was requested. |
| Manifest build or run | `<project>/.x2c-build/<target-product>` | Persistent per-target directories below the build root. |
| Script | Executable in the existing per-user script cache | Existing script retention and invalidation. |

Keep automatic job selection, the one-job default under Make, host optimization
defaults, and explicit selection of native debug information and source mapping.
Do not rename `a.out`, enable optimization, or change source mapping implicitly.
Those changes were not survey recommendations.

Document that one manifest target is selected automatically. Multiple targets
need `--target` or `project.default-target`. A profile applies only when selected;
a profile named `release` is not implicitly active.

### 2. Create requested translation directories

`translate --out-dir generated main.x` creates `generated` and missing parents.
Omitting `--out-dir` continues to mean `.`. Existing directories still work.

Validate input files, supported source types, and shared output stems before
creating the output directory or writing generated files. Keep rejection of
colliding translation stems. Inspection modes and dry runs create nothing.
An existing non-directory or a filesystem failure remains a failed command.
Use the existing path operation and error handling; do not add a directory
creation subsystem or repeated existence checks after successful creation.

### 3. Use one retained directory and reuse its results

All retained native build directories use the existing state and fingerprint
implementation. No second cache or state format is introduced.

- Bare `--save-temps` retains a direct build in `.x2c-build` and enables reuse.
- `--save-temps=<dir>` is a directory-selection spelling for `--build-dir <dir>`.
- If several named directory options occur, the last named option wins,
  regardless of spelling. Bare `--save-temps` never resets a named directory.
- `--compile-commands <file>` retains intermediates as today and now benefits
  from reuse. It does not override a named build directory.
- A manifest keeps its existing configured or default build root when given
  bare `--save-temps`. A named save-temporary directory overrides the manifest
  build root exactly as `--build-dir` does, instead of being ignored.
- Direct-build directory arguments remain relative to the invocation directory.
  Manifest fields remain relative to the project root. CLI directory overrides
  remain relative to the invocation directory.

Keep one `build_dir` request field for named directory choices. Delete
`temps_dir` and its precedence branch. Keep the existing retention flag for
bare `--save-temps` and compilation-database retention. Create the existing
state directory whenever a native work directory is retained, rather than only
when `build_dir` was explicitly supplied.

The existing successful-build cleanup, failed-build retention, script locks,
fingerprints, and compilation-database publication remain the owners of their
current guarantees. Do not add locks or new retention modes.

### 4. Default multiple compile-only outputs to the working directory

`build -c first.x second.c` produces `./first.o` and `./second.o`. No build
directory argument is required. Intermediates keep the ordinary temporary
lifetime, and the object products survive successful cleanup.

Preserve existing explicit-directory behavior: multiple compile-only inputs
with a named `--build-dir`, or its `--save-temps=<dir>` spelling, write objects
to the existing path-derived names below `<dir>/obj/`. This continues to support
inputs with matching basenames. Bare `--save-temps` retains intermediates but
does not move the default object products from `.`.

Keep single-input object naming and explicit `--output` behavior unchanged.
Multiple compile-only inputs still reject a single `--output`. Native objects
and archives remain invalid compile-only inputs.

For the new flat output mode, reject inputs that resolve to the same object
destination before translation or compilation starts. For example, `a/item.x`
and `b/item.c` cannot both write `./item.o`. Name the colliding inputs and tell
the user to select a build directory. Do not silently overwrite one product.
Use the original input stems; generated-directory hashes must not become the
default public object names. Actual object destinations must also appear in
receipts and compilation-database entries.

### 5. Accept the familiar native output spelling

Accept `-o <file>` and `-o<file>` as aliases of `--output <file>` for `build`
and `run`, including manifest builds. Repeated output options follow the
existing last-value rule.

Give the existing output option row the short spelling `-o` and long alias
`--output`, so the current short-option parser handles attached values.
Remove the early rejection for these commands. Do not add a second parser.

`translate` retains `--out-dir`; `-o` does not acquire a directory meaning.
Top-level and translation diagnostics must describe the accepted spellings
accurately, rather than claiming that `-o` is globally removed. The missing
command suggestion should use `translate <input>` without implying that an
output directory must be supplied.

### 6. Reject empty build directories and clarify debugging

Reject both `--build-dir=` and `--build-dir ""` through the existing missing
option-value diagnostic, as for `--output` and `--out-dir`.
Keep the existing empty `--save-temps=` rejection. Do not broaden this work
into validation of every native tool argument or environment variable.

Help and the book distinguish these options next to the build examples:

- `--debug` enables logging inside the x2c compiler.
- `-g` requests native debug information.
- `--source-map` maps generated C locations to the original x2c sources.

Show the existing `-g --source-map -O0` workflow for source debugging. Explain
retention when a user wants to inspect generated C. Preserve the documented
macOS symbol-bundle behavior.

## Documentation and executable selection

Prefer `./x2c` whenever a command example runs from the repository root.
State that working-directory prerequisite before commands using repository
paths such as `examples/`, `src/`, or `packages/`.

The inspected root link is `x2c -> builds/0/x2c`, not `bin/x2c`. After
`make build-safe`, `bin/x2c` points to `x2c-bootstrap`. `make build-install`
copies stage 0 to `bin/x2c-<branch>` and repoints `bin/x2c` to that copy.
Document these roles accurately; do not change the symlinks or build targets.
The root link selects the current stage 0 build without depending on PATH.

Installed-user examples retain `x2c` after explicit installation and PATH
setup. After `cd` into a new project, `./x2c` would name a nonexistent compiler
inside that project. A checkout-only walkthrough that changes directories
captures an absolute checkout compiler path first and invokes that path.
Keep explicit stage paths where the purpose is testing a particular stage.

Update these authored surfaces together:

- `docs/src/reference/cli.md`: lead with minimal commands; include the product
  and lifetime table, manifest defaults, directory-option equivalence and
  ordering, compile-only naming, aliases, and debugging distinctions.
- `README.md`, `docs/src/guide/installation.md`, and
  `docs/src/guide/from-c.md`: use the simplest workflow for each purpose and
  make checkout versus installed execution explicit.
- `examples/README.md` and relevant example or package instructions: use
  `./x2c` for repository-root examples; preserve context for other directories.
- `agents/quick-start.md`, `agents/x2c-debugging-guide.md`, and relevant
  developer references: reflect the new behavior and accurate compiler roles.
- `src/cli/help.x` and `src/cli/parsing.x`: expose defaults and aliases in
  generated help, without duplicating parser defaults in a second table.

Keep explicit scratch paths in debugging examples, isolation paths in tests,
and destinations owned by Make or tools. Do not remove options mechanically.
Use `run` when executing is the example's purpose; show `build` when retaining
an artifact is the purpose. Keep shell transcript paths consistent with the
artifact names. Fix the stray "The" before "A project" in the CLI reference.
Do not hand-edit generated API documentation or bootstrap files.

## Implementation sequence

1. Read the current task owners and instructions again. Confirm the working
   tree and baseline before implementation; preserve unrelated work.
2. Update the option row, empty-directory handling, directory normalization,
   and help. Remove `temps_dir` and update all request consumers.
3. Enable existing build-state reuse for retained directories and apply named
   save-temporary directories through normal manifest planning.
4. Create translation directories after input and stem preflight, preserving
   dry-run and inspection behavior.
5. Remove the multiple-input directory requirement. Select public object
   destinations and reject flat-output collisions at build preparation.
6. Update the existing CLI probes and documentation for the connected behavior.
   Execute representative examples in the working directories they describe.
7. Review and fix the complete authored diff for direct source, deletion,
   reused owners, compatibility, and complete coverage of this plan. This is
   the last implementation step before publication validation.

## Validation and delivery

Extend the existing CLI boundary probe rather than adding a test target or
recurring requirement. Replace assertions for intentionally changed behavior;
preserve unaffected checks and checked-in expectations.

| Behavior | Focused evidence |
| --- | --- |
| Existing defaults | Translation into `.`; `a.out`; one `.o`; library/module names; temporary direct run; manifest target product. |
| Directory creation | A missing nested translation directory succeeds; invalid inputs create no output directory; dry run and inspection create nothing. |
| Retention and reuse | Repeat direct builds with bare/named save-temporary options and a named build directory; verify reuse, retained files, and rebuild after an input change. |
| Directory ordering | Both orders of the named options select the last directory; bare retention does not reset it; manifest overrides work from a nested working directory. |
| Compile-only products | Mixed `.x`/`.c` inputs produce usable objects in `.`; link those objects; preserve single-output and explicit-directory behavior; compilation database names the actual objects. |
| Flat-output collision | Same-stem inputs fail before producing objects; a named build directory permits them. |
| Native output alias | Separate and attached `-o`, long output spelling, and last-value order select the expected product for build/run; translation retains its directory option. |
| Empty directory | Both empty build-directory spellings fail with the existing missing-value diagnostic. |
| Examples and help | Run representative checkout-root and installed/project commands with the specified compiler; inspect help against the decided defaults. |

Keep filesystem-failure coverage in the existing probe; update the obsolete
missing-directory expectation to the new successful behavior. Keep the
existing ambiguous multiple-output rejection coverage. Avoid new negative
fixtures whose only benefit is earlier rejection.

For implementation delivery, use the root repository workflow. Direct delivery
remains the default unless Gary selects another mode. Review generated changes,
run `git diff --check`, and ensure `tools/gate-state.py ensure agent-pr-check`
on the completed integrated tree. The gate owns final bootstrap refresh and
correctness validation. Follow the existing performance-checkpoint guidance
because retained-build reuse changes build orchestration; reuse the existing
workload rather than adding a benchmark or threshold.

## Implementation and verification record (2026-10-21)

The authored change is in `c91d7ed43`. It includes the six decisions, examples,
help expectations, and existing CLI boundary probe updates. The independent
review found documentation omissions, which were corrected. Source review also
corrected the multiple-object receipt to report the actual product directory.

A new run probe reproduced an existing executable-selection defect: a bare
relative `--output app` caused the driver to search PATH instead of launching
its own product. The driver now launches the absolute artifact path. Both
`run -oapp` and `run --output app` pass, including manifest execution.

Verification completed:

- `make build` and the gate's regenerated-bootstrap stage-0 rebuild succeeded.
- The focused defaults probe passed, including retention/reuse, changed-input
  rebuilds, directory ordering, mixed object linking, collisions, aliases,
  compilation databases, and manifest overrides from a nested directory.
- `unittest/probes/run-cli-boundary.sh` passed in full on the final script.
  The earlier run was invalidated by editing the script during execution;
  its shell-reading failure was not a product failure.
- `make commands` and `make doc-check` passed. The documentation audit checked
  183 files, 417 linked files, and 20 path-audited entry points.
- Representative checkout execution, retained executable, translation plus
  external C compilation, and project creation/run examples passed. Project
  commands were checked using an absolute checkout compiler and PATH selection;
  a new installed prefix was not created.
- `make doc-generate` refreshed derived documentation. The publication command
  regenerated bootstrap artifacts, whose changes were reviewed against source.

`tools/gate-state.py ensure agent-pr-check` failed at stage 1. Fatal-warning
translation reports a region warning at `lib/thread.x:563` concerning the
address of local `run` stored through an unknown pointer. The CLI change does
not edit that file. An isolated archive of clean `origin/dev` at the planning
baseline, built with `make build-safe stage-1`, fails with the same warning.
The cause and correctness of the thread lifetime diagnostic remain unadjudicated.

Evidence remains in the worktree's `debug/cli-publication.log`,
`debug/cli-boundary-final.log`, `debug/cli-doc-check.log`, and
`debug/cli-examples.log`. The preserved baseline is named by
`debug/cli-baseline-path`; its log is `debug/stage-1.log` within that tree.

Gary subsequently authorized delivery despite this warning, with its separate
repair underway in another worktree. For this delivery only, run
`make agent-pr-check STRICT_X2C_FLAGS=`. This leaves native `-Werror` intact
and permits the remaining correctness checks and self-host comparisons to run.
Inspect all warnings and stop for any additional failure; do not record the
normal `agent-pr-check` as green. Complete the existing performance checkpoint
after the self-host comparisons. The exception changes no repository target
or recurring requirement.

The first exception run passed self-host comparisons, cold collection,
documentation, 1,246 compiler fixtures, and all 976 runtime tests (26,314
assertions). Command checks exposed baseline lint violations: five over-width
lines and six wrapped openings in unchanged `lib/thread.x` and `lib/pool/pool.x`.
Those lines were reformatted without changing executable tokens or behavior;
the lint baseline was not raised. Derived Thread documentation was regenerated.
Lint's subject-name rule also required the standard `Iter i` parameter
spelling in `Iter.parallel_map`; its signature and initializer were updated
together. The complete `sh commands/lint/tests/run.sh` check now passes.
The separate lifetime repair remains outside this change. Rerun the exception
gate on this completed tree before delivery.

The completed exception gate subsequently passed at `fd6e0c61`. The existing
build-cost checkpoint measured 54.902535 median CPU seconds across 90,137
authored source lines, scoring 84.9 against the pinned baseline of 100. It
used `tools/build-scaling.py --compiler builds/1/x2c --ref HEAD`, with a
temporary `MAKEFILES` override containing `override STRICT_X2C_FLAGS :=` to
apply the same warning exception during its three stage builds. This was an
observation against the historical baseline, not an isolated CLI speedup.

The direct push was rejected because `origin/dev` advanced to `bc0277a63`.
Its `81a76f090` thread repair is now integrated, together with the upstream
c2x2c documentation changes. The authored Thread formatting and parameter
rename were preserved. Generated merge conflicts were resolved by regeneration
from the merged authoritative source, not by editing generated C or prose.
Repeat the normal `tools/gate-state.py ensure agent-pr-check` and the existing
performance checkpoint on this integrated tree. The exception is historical;
normal warning policy now applies.

## Plan review

- CLI parsing owns option spellings and required values. Build preparation
  owns product destinations and collision detection. Translation preflight
  owns source/stem acceptance; successful path creation establishes directory
  creation. Consumers do not repeat these guarantees.
- Reuse `Path.make_dirs`, native action construction, fingerprints, retained
  state, cleanup, option tables, and the existing probe. Delete `temps_dir`,
  its precedence path, and the multiple-input directory requirement. No new
  cache, request mode, locking scheme, or generic build framework is needed.
- Keep path selection as short operations beside existing product preparation
  and compilation. Use ordinary Lists, Maps, and path operations. A shared
  destination calculation earns its place only if preflight and compilation
  both need it; do not duplicate their naming rule.
- The one new semantic rejection is a colliding flat object destination. Its
  diagnostic and negative probe prevent overwritten products and parallel
  writes to one file. Empty build-directory rejection reuses the existing
  option-value diagnostic and protects the deliberately stated CLI contract.
  Existing filesystem, ambiguous-output, and unsupported-input checks retain
  their current purposes. Add no other validators or dedicated diagnostics.
- Compatibility changes are explicit: missing translation directories now work;
  retained builds reuse; named directory options use command-line order;
  manifest save-temporary directories take effect; multiple compile-only
  inputs gain a default; native `-o` works; empty build directories fail.
  Existing product names, configured paths, host defaults, and temporary direct
  builds remain intact. No consequential design question remains open.
