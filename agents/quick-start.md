# X2C Quick Start

Use this page for current commands and repository orientation. The root
`AGENTS.md` owns workflow and publication rules.

## Build and validate

From a fresh worktree, or after integrating a changed `bootstrap/`:

```sh
mkdir -p debug
make build-safe >debug/bootstrap.log 2>&1
```

Use `make build` when a source change needs a current compiler. It uses
`stage0-settle`: refresh the symbol snapshot when its inputs changed, rebuild
stage 0, and confirm that the rebuilt compiler agrees. Use a focused compiler
invocation or test to answer the question being worked on. The root
[Verify and deliver](../AGENTS.md#verify-and-deliver) section owns final
validation and publication; the commands below are a reference, not another
required sequence.

| Command | Purpose |
| --- | --- |
| `make verify` | Unit suites, compiler fixtures, and focused probes. |
| `make stage-3` | Build through the third self-hosted stage. |
| `make stage-diff-all` | Compare generated C/H file sets and bytes across stages. |
| `make check` | Standalone extended non-mutating checks. |
| `make verify-fixtures` | Check exact compiler fixture artifacts without rewriting them. |
| `make verify-fixtures-update` | Accept an intentional, reviewed fixture-output change. |
| `make sym-check` | Check the deterministic compiler symbol snapshot. |
| `make sym-refresh` | Refresh symbols, verify regeneration, and display the diff. |
| `make sym-update` | Accept an intentional, reviewed symbol change. |
| `make proof-conformance` | Optional snapshot/live protocol conformance comparison. |
| `make examples` | Check the curated executable examples manifest. |
| `make examples-update` | Accept intentional, reviewed example-output changes. |
| `make doc-examples` | Compile the book's code examples; optional. |
| `make packages-check` | Check packages with their prepared dependency cache; outside `check`. |
| `make artifact-refresh` | Refresh symbols and bootstrap; does not establish publication readiness. |
| `make sanity-check` | Refresh bootstrap, rebuild stage 0, and build through stage 3 without checks. |

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
`plans/x2c-correctness-performance-tooling.md` records the full comparison.

`make precommit` checks symbols, refreshes header symbols and bootstrap,
rebuilds stage 0 safely, builds through stage 2, and compares stages 0, 1,
and 2. `agent-pr-check` runs it and the remaining extended checks. Stage 2
establishes self-host convergence; the fourth build is available on demand.

Source changes can leave `stage-diff-0` red until bootstrap is regenerated:
it compares checked-in bootstrap C/H with stage 0 output. The publication
command owns that refresh; inspect its generated diff. Use the individual
self-host stage comparisons when a staged language transition needs evidence
before an explicit bootstrap refresh.

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
cc -iquote include /tmp/x2c-example/foreach.c \
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
- `etc/` - shared build rules, symbol snapshot, Lisp bootstrap, and SDK.
- `packages/` - optional third-party adapters, outside `make check`.
- `site/` - public website; it is not gated.

`agents/x2c-module-catalog.md` is generated from current source. Run
`make doc-check` to verify it.

## Implementation landmarks

- Percent literals and lambdas: `src/literals.x`.
- Statements: `src/statements.x`; the built-in `foreach(item, collection)`
  source macro: `etc/builtin-macros.xmacro` and `etc/builtin-macros.xlisp`,
  loaded by `src/macros.x`.
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
