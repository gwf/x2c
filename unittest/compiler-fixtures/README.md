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
diagnostics for invalid or legacy forms.

Symbol fixtures keep the checked artifact focused by selecting entry headers
that contain the literal text in `<name>.symbol-filter`. The matching entry's
complete Type representation is compacted to one line and sorted by key.

To accept an intentional compiler change:

```sh
make verify-fixtures-update
git diff -- unittest/compiler-fixtures
make verify-fixtures
```

The update command rewrites every declared expectation. Never use it merely to
make a failing check pass; review each changed artifact as compiler behavior.
