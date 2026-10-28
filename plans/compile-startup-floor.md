> Status: reference
> Drafted 2026-10-28 against `gwf/repo-survey-major-features-933090`
> (`9aeeef265`) with `builds/0/x2c` identity `48fd687ab075ad6f`. No
> implementation had started when drafted. The probe corrected the premise:
> a converged tree already replays the prelude from `.xi` interfaces in about 70 ms;
> the 0.5-0.8 s cold walk is the cost of a stale stage. Gary decided on
> 2026-10-28: skip the replay floor change (phase 1 step 1), keep the
> stale-stage visibility in `x2c env`, and do the `run` cache.
> Implementation is complete locally. Shared-integrator submission owns
> final generated artifacts, the performance checkpoint, and the full gate.

# Compile startup floor

## Result

- Every command that opens a unit (`translate`, `build`, `run`, `script`,
  `repl`, `editor`) keeps replaying the runtime prelude from the stage's
  `.xi` interfaces; the converged empty-program `translate` floor stays at
  about 80 ms wall on the M4 Max host (the replay change that would reach
  60 ms was declined on 2026-10-28; see phase 1).
- `x2c env` reports a prelude interface only when it validates as the
  compiler would replay it, so a stale stage (edited `lib/` source without
  a rebuilt stage) is visible instead of silently costing 0.4 s per process.
- `x2c run` reuses a cached executable for unchanged inputs, through the
  `script` cache's entry layout, fingerprint, lock, and pruning; a warm
  `run` of an unchanged program costs what a warm `script` costs.
- No language syntax changes, no second interface format, no new symbol
  table state.

## Probe (2026-10-28, M4 Max, `builds/0` from `45c552a98`)

The premise was measured in this worktree, where `lib/` sources changed at
06:19 (`fe9af203d`..`f5d0eb2fb`) after the stage was built at 05:39. The
`.xi` dependency hashes (for example `lib/array/array.x 13d6094d`) no
longer match, so `_interface_read` rejects `lib/x2c.xi` and `_add_prelude`
walks `lib/x2c.x` cold. The compiler identity matches and the reader works;
only the content hashes differ. The same binary in a copy of the sources at
`45c552a98` (the tree the stage was built from) replays the prelude:

| Workload (`translate -q`) | stale stage | converged stage |
| --- | --- | --- |
| `int main(void){return 0;}` | 0.81 s | 0.08 s |
| `examples/foreach.x` | 0.45 s | 0.08 s |
| `examples/tours/language.x` | 0.44 s | 0.08 s |
| `src/expressions/expressions.x` | 1.42 s | 0.47 s |
| `run -q empty.x` (temporary build dir) | 0.75 s | 0.15 s |
| `script empty.x`, warm | 0.04 s | 0.04-0.10 s |
| `x2c env` | 0.01 s | 0.01 s |

Ten empty units in one process take 0.135 s, so one unit costs about 6 ms
and the per-process fixed cost is about 75 ms, of which process start is
under 5 ms. `--no-cpp` does not change the floor; `load_prelude` clears the
dump and symbol modes before collecting.

What the cold walk does (stale tree, `sample`): 410 of 436 samples are
under `Frontend_load_prelude` -> `Compiler_collect_symbols` ->
`_walk_file(lib/x2c.x)` -> `_include_file` -> `_walk_cold`, recursing
through the 37 runtime units in include order. Each `_walk_cold` opens a
child `Compiler` (`interface_provider = 1`), splits the file at its
includes, and shallow-parses each segment (`shallow_parse_overlay`) into a
declaration overlay: declarations, types, macros, keyword aliases, protocol
rows, and declaration defaults. `_publish` retains the entry
`(parts hash definitions dependencies include-roots)` in the process cache;
`parts` is the ordered list of declaration Maps and included canonical
paths. The replayed entry has the same shape: `_replay_cached` merges each
Map into `globs`, replays included paths through `_replay_include`, records
function definitions and dependencies, and installs package imports. In a
stage build the first unit's prelude walk produces these entries and each
unit's `.xi` is written from them, so a stage's runtime interfaces are the
cold-walk entries spelled out (`_publish` keeps the first entry).

Where the converged 80 ms goes (`xctrace` Time Profiler, 88 samples):

| Inclusive | Function | Note |
| --- | --- | --- |
| 72 | `Frontend_load_prelude` | 37 unit interfaces, 1.64 MB |
| 27 | `_read_record` / `String_read_lisp_form` | datum parse |
| 24 | `_read_rows` -> `List_try_own` -> `Pool_own` | ownership walk per row |
| 15 | `__open_nocancel`, `access`, `Path_real` | candidate probing |
| 8 | `_replay_package_imports` | |
| 7 | `_read_dependencies` | 37 source hashes |
| 4 | `_initialize_environment` -> `fnv_file` | identity of the 3.4 MB binary |

A script using the same reader (`String.read_lisp_form`) reads the 37
prelude interfaces (1,640,934 bytes) in 20.5 ms, all 70 `builds/0/lib`
interfaces (2.19 MB) in 23.5 ms, hashes the 37 sources (461,621 bytes) in
0.6 ms, and builds and merges their 5,756 rows into Maps in 0.8 ms. The
`--dump-symbols` output for the empty program has 5,684 rows (7.5 MB).
The reader is not the bottleneck; the ownership walk and filesystem probing
are, and a binary image would remove only the 21 ms parse.

## Decisions

1. Representation: the textual `.xi` interface, unchanged. A binary or
   mmap image is rejected: the measured parse is 21 of 80 ms, and a second
   format would need its own writer, reader, validation, and cold-collection
   proof beside the one `proof-cold-collection` already checks.
2. Location and writer: unchanged. The prelude image is
   `builds/N/lib/x2c.xi` plus the 37 unit interfaces beside it, written by
   the `lib` batch in `etc/x2c.mk` and keyed by compiler identity and
   source content hashes as today. No write-through cache for cold walks:
   a tree whose `lib/` sources changed also has a stale `libx2c.a`, so the
   right action in that gap is `make build`, which rewrites the interfaces.
3. Consumption: `load_prelude` keeps its path through `_add_prelude` ->
   `_prelude_entry` -> `_entry` -> `_interface_read` -> `_replay_cached`.
   The proposed allocation change inside `_interface_load` was declined.
   `_read_rows` keeps its ownership walk. Nothing changes in replay.
4. Visibility: `x2c env prelude` and `prelude_missing` validate through
   `_interface_read` (identity, path, hash, include roots, dependency
   hashes) instead of the identity header alone, so a stale stage prints an
   empty `prelude` and lists stale units. `env` pays about 60 ms for it.
5. Correctness: `--dump-symbols` of the empty program is byte-identical
   before and after; `make verify-fixtures` and `proof-cold-collection`
   pass; stage comparisons in `agent-pr-check` are unchanged.
6. `run` cache: `run` with explicit inputs and none of `-o`,
   `--build-dir`, `--save-temps`, `--compile-commands`, or a manifest
   builds under `<cache_root>/runs/STEM-HASH` with `script`'s lock, record,
   fingerprint, pruning, `--rebuild`, and `--clean`, and executes the cached
   executable when `script_current` says it is current.
7. REPL and editor: `repl_run` opens its session through
   `Frontend.open_session`, and `editor` through `Frontend.open`; both
   collect with `c.prelude = 1` and reach the same `_prelude_entry`, so
   their collection path stays unchanged. Nothing to change there.
8. Measurement: the table above is the baseline; repeat it after each
   phase on the same host, converged tree, alternating runs, per
   `agents/performance-checkpoints.md`.

## Phase 1: stale-stage visibility

Settled 2026-10-28: step 1 below is not done. A 20 ms change to how
parsed interface records are retained is below what a user notices, and
the gate would not detect a subtle retention regression. Steps 2 and 3
stand; step 4 measures only `x2c env`. The probe table stays as the
record of the converged floor.

Files: `src/collect/interfaces.x`, `src/utils.x` (or wherever `x2c env`
builds its rows), `docs/src/reference/cli.md` (Environment),
`docs/src/internals/architecture.md` (Unit interfaces),
`agents/performance-checkpoints.md`.

1. In `_interface_load`, read the file text in the unit scope as now and
   parse the one form under `auto (&process_cache_scope)`. In
   `_read_rows`, store each `(key value)` pair without
   `_require_retained(pair.try_own())`; keep `_retain` for the rebuilt
   `(meta-hashes ...)` value, which is constructed. Keep `_retain(canonical)`
   and `_require_retained(entry.try_own())` in `_interface_entry`; they
   cover the five-element entry, not its rows. First verify with a probe
   that `try_own` is a no-op for cells born under the cache scope; if the
   pool model still needs the walk, drop this step and keep steps 2-3, and
   record the floor as unchanged.
   A record rejected after parsing stays allocated until process exit, the
   lifetime its validated siblings already have; the prelude's 37 records
   are 1.64 MB of text, so measure the resident delta and expect under
   4 MB.
2. `Compiler.prelude_interface` returns the candidate only when
   `_interface_read` accepts it for a compiler configured as `load_prelude`
   configures one (default include dirs, no package). `prelude_missing`
   lists each included unit whose `_entry` is NULL under that compiler.
   Both run inside `x2c env` only.
3. Documentation: cli.md's Environment paragraph says `prelude` is the
   interface the compiler will replay, and an empty value means a source
   or stage change invalidated it; architecture.md keeps its description
   and loses nothing. performance-checkpoints.md replaces "check that
   `x2c env` prints a non-empty `prelude`" with the same words, now true.
4. Measure: empty program, `foreach.x`, the tour, `expressions.x`, and
   one `make stage-1` wall time, before and after, in the plan.

For the record: step 1 would have reached about 60 ms wall for the empty
program (from 80). Under 50 ms is not reachable without the rejected
second format or a change to candidate precedence (the 15 ms of probing
opens up to six candidate paths per unit in a fixed order that the
architecture documents). Neither is planned.

Size: about 20 changed lines in `interfaces.x`, 15 in `env`, 15 of
documentation.

## Phase 2: `run` reuses the script cache

Files: `commands/build/script.x`, `commands/build/workflow.x`,
`src/cli/parsing.x`, `docs/src/reference/cli.md` (Build and run, Run a
script), `commands/build/tests/run.sh`.

1. `CliRequest.prepare_script` becomes the cached launch for both
   commands. The entry is `scripts/STEM-HASH` for `script` and
   `runs/STEM-HASH` for `run`, where `STEM` is the first input's stem and
   `HASH` hashes the absolute input paths joined by newlines. `source`
   records the first input; `_prune` walks both directories and removes
   entries whose first input no longer exists, as today.
2. `run` takes the cached path only with explicit inputs and none of
   `-o`, `--build-dir`, `--save-temps`, `--compile-commands`, or a
   manifest; `-###` prints the actions as now. Every other `run` keeps the
   temporary build. `script` is unchanged except for the shared code.
3. On the cached path `run` does what `script` does: `_exec_current`
   before any compiler state loads, then lock, build, `publish_script`,
   `run_script`. The fingerprint is `_script_fingerprint` unchanged: it
   already covers the inputs list, translation options, linker arguments,
   environment, every prerequisite file, and search directories. `run`
   does not translate `script_helpers`; its program is its listed inputs,
   which is why the two commands never share an entry.
4. Launch: a cached or freshly built `run` on this path execs the
   executable with `argv[0]` set to the first input's absolute path, as
   `script` does, and the program's exit status is the command's. A cached
   launch prints nothing but the program's output; `-v` prints the run
   action. A rebuild prints `run`'s ordinary progress and receipt unless
   `-q`.
5. `--rebuild` and `--clean` accept `run` in `parsing.x`.
6. cli.md: "Build and run" gains one paragraph saying that `run` without
   an output location caches its executable like `script`, names the
   `runs/` directory, the invalidation rule by reference to the script
   paragraph, and the `argv[0]` convention. "Run a script" names both
   directories under the cache root.
7. Tests in `commands/build/tests/run.sh`: second `run` is cached (no
   build receipt, same output); editing the source rebuilds; `--rebuild`
   rebuilds; `--clean` removes the entry; `-o` and `--build-dir` keep the
   current behavior; two different inputs lists get two entries.

Size: about 60 changed lines in `script.x`, 15 in `workflow.x`, 4 in
`parsing.x`, 25 of documentation, 50 of tests.

## Validation

- Phase 1: `builds/0/x2c translate --dump-symbols empty.x` before and
  after, diffed; `make verify-fixtures`; `tools/gate-state.py ensure
  agent-pr-check` (includes `proof-cold-collection` and the stage
  comparisons); `x2c env` in a converged tree prints the prelude path and
  an empty `prelude_missing`, and in a tree with one edited `lib/` source
  prints an empty `prelude` and that unit.
- Phase 2: `commands/build/tests/run.sh`; `make commands-check`;
  `agent-pr-check`.
- Performance checkpoint for both phases: the probe table, alternating
  runs on the converged tree, recorded in this plan under a dated heading.

## Not attempted

- A write-through cache for cold prelude walks (decision 2).
- Candidate-path probing order (15 ms); the documented precedence stays.
- Hashing the compiler binary for its identity on every start (4 ms).
- The 37 source hashes per process (under 1 ms of CPU; the 7 samples are
  file opens).

## Plan review

- Established facts: the interface reader validates identity, path, hash,
  include roots, and dependency hashes before replay; `_publish` keeps a
  file's first entry, so stage interfaces are cold-walk entries; the
  script fingerprint covers everything a reused executable depends on.
  Phase 1 changes only the environment report's interface selection.
  Phase 2 calls the same fingerprint and lock; `env` calls the same
  validator the replay uses instead of its own header check.
- Deleted or reused: `_read_rows` keeps its per-row ownership walk;
  `_written_interface`'s header-only check is replaced by the replay reader
  for `env`; `run` reuses `prepare_script`, `publish_script`,
  `script_current`, `_prune`, `_exec`, and the `scripts/` layout under a
  second directory name. New lasting mechanisms: none. The `runs/`
  directory exists so a `script` entry and a `run` entry for the same file
  never overwrite each other's executable.
- Idiomatic: both phases compose existing operations (the interface
  reader and existing fingerprint) rather than adding a format, a
  daemon, or a second cache policy.
- Validators, diagnostics, negative fixtures: none new. The `run.sh`
  cases are positive behavior checks of the documented cache rules.

## Last step

Before publication validation, review the completed authored diff for the
same points: that no step rechecks a validated fact, that `run` shares
`script`'s code rather than copying it, that replay retention is unchanged,
and that documentation says what
`env` and `run` now do. Fix what the review finds, then run the
validation above.

## Implementation and handoff (2026-10-28)

Starting revision: `9805a4f3add3ea56ad7ff05bacf49f71bc13222f`.
Delivery uses the existing shared integrator, as Gary requested. This session
does not run the publication gate or regenerate the final bootstrap.

- `env` selects the prelude path through `_interface_load`, the same file
  validator `_interface_read` uses. Missing-unit reporting reads the stored
  include list even when the prelude is stale, then checks each unit with
  `_entry`. Both use the default include roots and no package.
- `run` shares script preparation, executable publication, fingerprinting,
  locking, pruning, and execution. Its cache key includes every absolute
  input path, in order. Ordinary output and manifest builds stay on their
  existing path. `--clean` and `--rebuild` require a cached launch.
- `_script_files` now records every input's translation dependencies, plus
  the native dependencies it already recorded. This is needed for a header
  used by the second input to invalidate a cached multi-input program.
- The isolated environment probe generated matching runtime interfaces with
  the current compiler. `prelude` was present and `prelude_missing` empty.
  Appending a newline to `lib/array/array.x` cleared `prelude` and listed that
  unit and its dependents. Restoring the source restored both report values.
  Five matching-fixture `env` samples had a median of 54 ms. This functional
  observation is not the final paired performance checkpoint.
- The authored diff retains all replay ownership operations and adds no
  interface format, cache fingerprint, or symbol-table state.
- `make build`, `sh commands/build/tests/run.sh`, and the saved isolated
  environment probe pass. Cache probes cover receipts, arguments, source
  edits, second-input headers, exit status, forced builds, removal, explicit
  outputs, retained directories, separate input lists, and dry runs.
- `unittest/probes/run-cli-boundary.sh` passes, including script caching,
  dependency invalidation, manifests, and explicit run outputs. Its former
  temporary-run assertion now checks the retained cache build.

The integrator owns final generated documentation and bootstrap, converged
performance measurements, and `agent-pr-check`. The focused documentation
audit currently reports only the expected generated `collect.md` API prose
changes for the two updated environment-report methods.

## Integration checkpoint, 2026-10-28

The selected implementation and validation are complete in PR #601. The
replay-retention optimization remains declined. This checkpoint compares
converged stage-zero compilers at baseline `f0b30539e` and combined candidate
`0cc41b984`, which also includes PR #600's JSON boolean export repair.
Both compilers report a valid prelude and no missing interfaces.

The table gives median wall milliseconds from five alternating baseline and
candidate runs on this Mac. Translation uses `-q` and temporary output
directories. Both execution commands use the same empty `main` program.
Each command is warmed before sampling and has an isolated cache directory.

| Workload | Baseline ms | Candidate ms |
| --- | ---: | ---: |
| `env` | 14.3 | 50.2 |
| `translate` empty program | 91.9 | 90.4 |
| `translate` foreach | 92.3 | 91.8 |
| `translate` language tour | 99.3 | 99.2 |
| `translate` expressions module | 538.6 | 533.7 |
| warm `run` empty program | 245.7 | 49.1 |
| warm `script` empty program | 46.5 | 46.1 |

`env` pays the intended validation cost. Cached `run` avoids translation,
compilation, and linking. `/usr/bin/time -l` reports median retired
instructions of 1,862,612,535 versus 313,179,583 for warm `run`, and
84,175,788 versus 596,327,596 for `env`. These instruction counts are
separate from the wall-time measurements.

The empty-program symbol dumps have identical sets of 5,860 key/value
records. Raw dump order differs, so the complete parsed records were
compared independently of order. The full publication gate passed for the
candidate. This measurement record is the only subsequent authored change.
Raw samples remain with the integration batch's `debug/startup-performance.json`.
