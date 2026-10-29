# Testing your project

Include `test.x` to write a test program. Decorate each
`static void name(void)` function with `$test()`, and finish the file with
`$test.main()`.

```x2c
#include "test.x"

$test()
static void push_then_pop(void) {
  Array stack = auto [];
  stack.push(1);
  $expect_eq(stack[0], 1);
  stack.pop();
  $expect(stack.len() == 0);
}

$test.main();
```

Tests register before `main` and run in declaration order. Run a file
directly with `x2c run tests/stack_test.x`, or run the project's test files
with `x2c test`.

## Assertions and skipped tests

`$expect(condition)` records the expression and its source location if the
condition is false. Execution continues, so a test can report several
failures. `$expect_eq(actual, expected)` evaluates each expression once,
boxes the values, and compares them with `Var.equal`, including its numeric
type distinctions. On failure, it prints both representations. Differing multiline Strings also produce a unified
difference, with `expected` first and `actual` second.

`$expect_raises(cause, statement)` passes only when the statement raises an
Error with the requested cause. Use a block for a statement sequence:

```x2c
~#include "test.x"
~$test()
~static void raises_bad_arg(void) {
$expect_raises(<bad-arg>, { raise %(bad-arg); });
~}
~$test.main();
```

An uncaught Error fails the test and reports its cause. `Test.skip(reason)`
stops the current test and marks it skipped. A failure recorded before a
skip still fails the test.

## Selecting tests

Each complete test program accepts:

- `--filter SUBSTRING` to run names containing that text. Repeat the option
  to select names matching any filter.
- `--list` to print selected names without running them.
- `--quiet` to omit passing test lines.

A normal run prints `ok NAME` or `FAIL NAME (file:line)` for each test,
then `N passed, M failed, K skipped`. A skipped test prints its reason.
The program returns 1 when a test fails, 2 when filters select no tests,
and 0 otherwise. A no-match run prints the zero-test summary even with
`--list`.

For example, `x2c run tests/stack_test.x -- --filter pop --quiet` selects
test names containing `pop`.

## Running test files

The command is experimental and available in checkout builds.
`make install` does not install it.

`x2c test` finds `*_test.x`, `test_*.x`, and every `.x` file below a
`tests/` directory. With no operands, it starts at the nearest `x2c.toml`
project directory, or the current directory when there is no manifest.
Pass files or directories to select a smaller search. Matching `tests/`
directories are inside the selected project or search root; an ancestor
named `tests` does not change discovery. Build directories under
`.x2c-build/` are excluded.

The command builds and runs each file through the matching compiler's
`script` command. Each file is a complete program. The script command
builds its local source includes. Package and x2c include directories come
from the selected project target. Use `--manifest FILE` and `--target NAME`
to select that configuration explicitly. The runner sets `X2C_CACHE_DIR`
for each job to `.x2c-build/tests/`, so script builds stay there.

For a direct invocation of a test that includes local source helpers, use
`x2c script tests/stack_test.x`. The `run` command is sufficient for files
that include only runtime modules.

Pass `--filter`, `--list`, and `--quiet` through `x2c test` to every test
program. Use `-j N` to run files concurrently. The runner captures each
file's output and prints complete file results in discovery order.
A final summary counts passing and failing files and tests. Files with no
tests matching the filters are omitted from output and file counts. The
command returns 2 when filters select no tests across the entire run,
including with `--list`. Discovery with no files also returns 2. Build
errors and test failures return 1 even if other files have no matching tests.
