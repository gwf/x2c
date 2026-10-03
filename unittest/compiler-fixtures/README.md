# Compiler fixtures

Each `.x` source has a one-line `.phases` file naming the exact artifacts that
the fixture checks. Supported phases are:

- `tokens` - non-trivia token types, text, and positions before preprocessing
- `ast` - parsed AST from `--dump-ast`
- `transform` - normalized AST from `--dump-transforms`
- `emit` - pre-generation emitted tokens from `--dump-code`
- `symbols` - `--dump-symbols` entries selected by the fixture's required
  `.symbol-filter` text
- `h`, `c` - final generated files
- `compile-status`, `diagnostics` - compiler failure status and stderr
- `stdout`, `stderr`, `status` - generated program behavior

An optional one-line `<name>.flags` file appends its whitespace-separated
contents to every translate invocation for that fixture. The package-prefix
fixtures use it for `--package-dir`; their `.x` sources are symlinks into
`packages/`, whose canonical paths select package-mode translation. The
`import-*` and `with-*` fixtures are ordinary consumers that import those
packages; the `leak` package under `packages/` exists to trigger the
unprefixed-surface diagnostic and is not a model package.

An optional one-line `<name>.stack-kb` file sets that fixture's soft compiler
stack limit in KiB.

Run checks from the repository root:

```sh
make verify-fixtures
```

Actual files are written under `unittest/build/compiler-fixtures/`. A mismatch
prints a unified diff and leaves the actual artifact there for inspection.
Generated native-runtime fixtures compile with the repository's active
`BUILD_CFLAGS`, so debug and optimized modes check the same declared behavior.
Runtime stderr keeps its unmodified bytes in `stderr.raw`. The checked
`stderr.actual` canonicalizes only Logger text-line clocks: the leading
elapsed time becomes `<elapsed>` and the first-event `start_time` value becomes
`<wall-time>`. Logger's unit suite tests those clock fields; compiler fixtures
check every other diagnostic byte and the exact exit status.
The type-initializer fixtures check lifecycle-hook generation and the exact
diagnostics for unsupported forms.

Symbol fixtures keep the checked artifact focused by selecting entry headers
that contain the literal text in `<name>.symbol-filter`. The matching entry's
complete Type representation is compacted to one line and sorted by key.

To accept an intentional compiler change:

```sh
make verify-fixtures-update
git diff -- unittest/compiler-fixtures
make verify-fixtures
```

The update command stages each fixture's declared expectations and rewrites
them only after that complete fixture succeeds. A failed or timed-out fixture
leaves its expectations unchanged; other successful fixtures may still update.
Never use it merely to make a failing check pass; review each changed artifact
as compiler behavior.

Fixtures run in parallel, using `JOBS` workers (the CPU count by default).
Check runs report each failure as its worker finishes and stop launching new
fixtures. Already running workers finish and retain their results. The next
suite checks previous failures first, then fixtures without a completed
result, then previous passes. Each group finishes before the next starts.
Every fixture must pass again in one complete run; previous results select
order and never permit skipping checks after an edit.

Retry hints live under `debug/fixture-retry/`, separately from actual outputs
and publication proof. They survive unit-build cleanup and source edits.
`FIXTURE_RETRY_STATE` selects another hint file for an isolated investigation.
Direct `--fixture` checks do not change suite hints. Update runs check every
fixture in normal order, even after a failure, and do not read or write hints.

Each complete fixture has a 60-second wall-clock limit covering translation,
native compilation, and program execution. Set `FIXTURE_TIMEOUT_SECONDS` to a
positive number for an intentional slow-machine investigation. The same limit
applies to direct `run.sh check --fixture <name>` and update runs.

A timeout is a harness failure, never an expected compiler or program status.
It reports immediately, preserves the fixture log and actual files, and stops
that worker's process group, escalating to kill after one second. Interrupting
the runner also stops active workers and their children. Completed runs report
elapsed time and the slowest fixture; each case keeps an `elapsed` file beside
its log and tally.
