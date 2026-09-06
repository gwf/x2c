# X2C Quick Start

Use this page for current commands and repository orientation. The root
`AGENTS.md` owns workflow and publication rules.

## Build and validate

From a fresh worktree, or after integrating a changed `bootstrap/`:

```sh
mkdir -p debug
make build-safe >debug/bootstrap.log 2>&1
```

For ordinary development:

```sh
make build
make verify
make stage-3
```

Batch connected work and run broad checks once on the integrated result. Use a
focused test or compiler invocation while editing only when it answers an
immediate question. Save complete failures under `debug/`.

`make build` uses `stage0-settle`: it refreshes the symbol snapshot only when
its inputs changed, rebuilds stage 0, and confirms that the rebuilt compiler
agrees. `make sym-refresh` intentionally refreshes and displays the symbol
artifact diff. `make sanity-check` is the recovery path that refreshes
bootstrap, rebuilds stage 0, and builds through stage 3 without running checks
or stage comparisons.

Use `make check` for the standalone extended non-mutating suite. Agents use
`tools/gate-state.py ensure agent-pr-check` before publishing code; it reuses
a valid result or runs the existing precommit proof and remaining extended
checks without building the self-hosting stages twice. The root `AGENTS.md`
has the exact publication rule.

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
  source macro: `src/macros.x` and `etc/compiler-sdk.xlisp`.
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
