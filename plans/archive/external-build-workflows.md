> Status: done; delivered in #237 (`b4f96d2e`) on 2026-10-16.
> Archived after the integration wave through #273 (`fab576c2`).
> The implementation evidence below records the submission, not pending work.
> Wave-closeout performance evidence is recorded below.

# External build, run, and script workflows

Keep `x2c build`, `x2c run`, and `x2c script`, implemented by one shipped
`x2c-build`. Direct invocation accepts the same operation followed by its
ordinary options. Script-language parsing and entry construction are unchanged.

## Ownership

- `src/translation.x` owns synchronous translation, inspections, workers,
  ordered diagnostics, and signal forwarding. `translate_request` accepts the
  existing `CliRequest`, optional per-input output directories, and an optional
  parent-process callback for starts and successful completions. It neither
  reads nor writes build state. Ordinary translation retains its reports.
- `commands/build/` owns target building, native actions, run execution, script
  cache locking, freshness, publication, pruning, and final process replacement.
  Command and target contexts retain their original lifetimes.
- `src/project.x` retains manifest parsing and planning for build and editor.
  Shared utilities own the cache root. Native toolchain primitives stay shared.
- The CLI tables remain the syntax authority. The driver reads initial
  arguments, then forwards that exact vector through `--driver-arguments`.
  The command parses it without repeating initial response-file expansion.
  Direct invocation uses the ordinary reader and parser.

## Bootstrap and identity

Each numeric stage archives its compiler objects except `main.o`, generates
its embedded identity, translates the command using its own `translate`, and
links `libexec/x2c-build` with native Make rules. Other commands reuse that
archive and identity. Their ordinary build loop excludes `build`.

External commands derive the stage from the matching driver. Compiler identity
still determines interface and module compatibility. Build and script state
also hashes the build executable, captured once before command contexts open.
Native module actions explicitly name the loader: the matching driver for
application modules, and the current host for compile-time modules.

## Verification and delivery

Use existing CLI, native module, meta-helper, meta-cache, editor, and package
probes. Add a focused command smoke for direct invocation, exactly-once argument
reading, stage selection, command-only cache invalidation, and missing/mismatched
commands. Update hand-built installations that invoke workflows. Check clean
bootstrap recovery and a later self-host stage, development and prefix installs,
and distribution command presence. No new recurring gate is added.

Compare cold build, unchanged build, and warm script startup against the saved
baseline on the same quiet host. Record absolute times and investigate material
regressions. Review the authored diff and submit focused evidence. The shared
integrator owns final generated artifacts and the publication gate.

## Plan review

The CLI establishes argument meaning; the translation service consumes that
request and produces the existing artifacts. Build alone decides reuse and
native work. Existing manifest parsing, runtime services, and command packaging
are reused. The callback replaces direct `Build` calls. The private argument
mode prevents double expansion without serializing requests. Native stage rules
break the self-build cycle. The additional executable identity prevents stale
reuse after command-only edits. Explicit loaders preserve native linking.

No grammar, parser, persistent service, artifact registry, or fallback is added.
Operation rejection protects the standalone command's deliberately limited
public syntax. Existing input and identity diagnostics remain intact.

## Implementation evidence (2026-10-16)

The extraction is implemented. Script-language parsing and implicit entry-point
construction were not changed. The authored diff was reviewed, including a
separate review of the native Make rules and compiler/command boundaries.

- A clean `make build-safe` constructed the command without an existing one.
  Final `make build`, ordinary command construction, `make stage-1`, and
  `make stage-diff-1` passed. Stage 0 and 1 have identical generated compiler
  and runtime C/H files (280 files).
- The existing CLI/build/run/script suite, meta-helper and meta-cache probes,
  package installation, editor, and REPL inspection/reload/source-load checks
  passed. Command smoke covers direct invocation, diagnostics files, response
  expansion, stage runtime and nested command selection, relative driver paths,
  command-only cache invalidation, and missing/mismatched commands.
- The native-module probe passed through its custom-compiler fixture, which
  exposed a missing generated-header search path. The saved baseline reproduced
  the same `../lib/type.h` failure. Adding the stage compiler-header directory
  repaired that fixture; rerunning its final custom-compiler section passed.
- Direct run/script argument and exit-status checks passed. An interrupted
  script link published no executable; its next invocation rebuilt and ran.
- Development installation and an installed prefix ran the existing
  hello-world example with identical output. The distribution archive contains
  `libexec/x2c/x2c-build` and the shipped-command manifest.
- Final stage and boundary checks were repeated after normalizing relative
  driver paths. Linux native Make invocation was inspected by dry-run; runtime
  execution was verified on macOS, not Linux.

At submission, no timing results were claimed. The saved baseline was revision
`3c537279f77db4a190ba605ff2829438168cc4dc`. A baseline toolchain and alternating
cold-build, unchanged-build, and warm-script measurement script are retained in
this workspace's temporary files and `.context/build-extraction/`. Both the
baseline and candidate stage 1 report usable prelude interfaces. The shared
integrator was assigned the quiet-host measurements and regression review.

Before final bootstrap refresh, the integrator must clean the stage through
`make build-safe`. Incremental directories can retain generated `src/build.*`
and `src/script.*` after their sources move; `bootstrap-refresh` copies stage
C/H globs. Final bootstrap and generated documentation remain integrator-owned.

## Wave closeout (2026-10-16)

The full snapshot of `fab576c2` completed stage comparisons, build scaling,
shootout, and runtime measurements. Its final compiler workload failed because
it requested `--live-symbols` for module units. The closeout removes that
unsupported mode while retaining the same default-mode sources and CSV keys.
The failed attempt remains `20261017T001121Z-fab576c27853` in performance history.
The corrected full snapshot passed at `c5c136b7`, run
`20261017T002054Z-c5c136b76c48`. The compiler and runtime sources are unchanged
from the landed wave at `fab576c2`. The reference revision `b4c16946` was then
measured again on the same host, run `20261017T002543Z-b4c1694632e3`, retained
under `debug/wave-closeout-baseline/` in the main checkout.

| Workload | Reference rerun | Closed wave |
| --- | ---: | ---: |
| Sequential stage build, child CPU seconds | 43.064 | 50.770 |
| Build through stage 3, elapsed seconds | 17.926 | 26.251 |
| Representative translation, stage 0, elapsed seconds | 2.072 | 3.338 |
| Representative translation, stage 1, elapsed seconds | 2.061 | 3.296 |

These increases persisted when the reference was repeated. The current build
CPU measurement also repeated at 50.763 and 50.770 seconds. They establish a
higher cost for building and translating this wave's source tree; they do not
isolate the cause or attribute it to the external-build extraction. The
representative inputs changed from flat files to module units, so these rows
are not identical-input compiler throughput measurements. The optional live
mode is absent from the new workload because module units cannot use it.

Remaining performance follow-up: isolate the cost across the wave's revisions
with a fixed source workload before choosing an optimization. No compiler or
runtime behavior was changed to conceal the measured difference.
