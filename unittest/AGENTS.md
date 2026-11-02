# Unit tests (`unittest/`)

Use the [agent directory](../agents/README.md) for task routing and the
[root instructions](../AGENTS.md) for final validation and failure logs.

## Harness

The [test standard](../agents/x2c-code-standard.md#tests-examples-and-samples)
owns suite style and fixture boundaries. Include `test-macros.x` before its
first use.

The harness fails a test on a failed assertion, zero assertions, or extra
pushed/retained scope state. Ambient errors remain with their configured
policy owner. `TestHarness_skip` inside a running test makes that test a
skip unless it also fails: it needs no assertions and counts once. Outside
a test, the call registers one skipped test.

## Fixtures and lifetimes

- Choose `Scope.open` by allocation lifetime and guarantee release on every
  exit. Lists and interned Strings have long-lived owners; Vars may still hold
  mutable Array or Map values.
- Keep tests deterministic. Close files, free short-lived backing storage, and
  remove `/tmp` artifacts.

## Test support

- Test-only helpers stay under `unittest/`; do not add public runtime surface
  solely for a test.
- A newly exposed production defect is recorded in `unittest/STATUS.md` and
  handled in a focused follow-up unless the current goal authorizes the fix.
- Temporary outputs belong in `unittest/build/` or `/tmp`; never commit them.
- Update `STATUS.md` when a skip, gap, or harness contract changes.
- A new probe under `probes/` is either wired into a Make target or
  labelled optional in its header. `make verify` runs `run-suite-coverage`,
  `run-scope-shutdown`, `run-error-floor`, and `run-varops-fatal.sh`, and,
  through the `compiler-fixtures` target, `run-cli-boundary.sh`,
  `run-preprocessor-boundary.sh`, `run-symbol-snapshot.sh`,
  `run-header-cache.sh`, `run-protocol-boundaries.sh`,
  `run-expression-bodied-functions.sh`, and the four `run-meta-*.sh`
  scripts.

## Compiler fixtures

The [fixture runner reference](compiler-fixtures/README.md) owns phase files,
expected and actual artifact paths, native-warning expectations, compiler
variants, and intentional expectation updates.
