# Unit tests (`unittest/`)

Use the [agent directory](../agents/README.md) for task routing and the
[root instructions](../AGENTS.md) for final validation and failure logs.

## Harness

- Suites are `test-<feature>.x`. Tests are `static void` functions. Import
  `test-macros.xmacro` before its first use. Use `$test.scoped();` when a test
  owns one whole-function retained Scope, and `$test.run(function_name)` when
  the label is the exact function name. Keep intentionally descriptive labels
  as explicit `TestHarness_run` calls.
  Register `void <name>_suite(void)` suites in `test-all.x` with
  `$test.suite(suite_name)`.
- Call `EXPECT_*` and `TEST_FAIL` as bare statements. Do not return status or
  thread an `ok` flag.
- The harness fails a test on a failed assertion, zero assertions, or extra
  pushed/retained scope state. Ambient errors remain with their configured
  policy owner.
- Register deliberate deferrals with `TestHarness_skip(name, reason)` so
  they remain visible in the results.
- Guard a dependent dereference with `if (!EXPECT_X(...)) return;` only when
  continuing would be unsafe.

## Fixtures and lifetimes

- Choose `Scope.retain` by allocation lifetime and guarantee release on every
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

## Compiler fixtures

- Fixtures and checked-in expectations are in `compiler-fixtures/`; generated
  actual artifacts are in `build/compiler-fixtures/`.
- Each `.phases` file declares the exact sidecars owned by that fixture.
- `make verify-fixtures` checks expectations and never rewrites them.
- `make verify-fixtures-update` rewrites declared sidecars. Use it only for
  an intentional compiler change and review every resulting diff.
- Keep fixture programs small. Assert only the phase boundaries that the
  fixture is meant to own.
