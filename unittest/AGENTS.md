# Unit tests (`unittest/`)

Use the [agent directory](../agents/README.md) for task routing and the
[root instructions](../AGENTS.md) for final validation and failure logs.

## Harness

- Write suites, tests, assertions, and registrations as
  [TE-1](../agents/x2c-code-standard.md#tests-examples-and-samples)
  specifies. Include `test-macros.x` before its first use.
- The harness fails a test on a failed assertion, zero assertions, or extra
  pushed/retained scope state. Ambient errors remain with their configured
  policy owner.

## Fixtures and lifetimes

- Choose `Scope.open` by allocation lifetime and guarantee release on every
  exit. Lists and interned Strings have long-lived owners; Vars may still hold
  mutable Array or Map values.
- Restore mutable globals and capture targets in `finally` before freeing their
  fixtures.
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

- Fixtures and checked-in expectations are in `compiler-fixtures/`; generated
  actual artifacts are in `build/compiler-fixtures/`.
- Each `.phases` file declares the exact sidecars owned by that fixture.
- A fixture that runs its program must compile it without a C compiler
  warning. A fixture whose generated C warns on purpose declares `cc-stderr`
  and owns the warnings in `<name>.cc-stderr`; every other fixture fails on
  any warning, in check and update alike, so a new one is declared
  deliberately. `<name>.cc-stderr` records clang's text; a gcc run checks
  `<name>.cc-stderr.gcc` instead when it exists, and an update writes that
  file only when gcc's text differs.
- `make verify-fixtures` checks expectations and never rewrites them.
- `make verify-fixtures-update` rewrites declared sidecars. Use it only for
  an intentional compiler change and review every resulting diff.
- Keep fixture programs small. Assert only the phase boundaries that the
  fixture is meant to own.
