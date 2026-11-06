# Compiler and runtime tests

This directory tests the repository itself; to test your own project, see
[Testing your project](../docs/src/guide/testing.md).

- `test-*.x` are runtime and language suites, linked into one `test-all`
  program that [test-all.x](test-all.x) registers.
- [compiler-fixtures/](compiler-fixtures/README.md) compares compiler phase
  output with checked-in expectations.
- `probes/` holds scripted checks of the command line, compiler caches,
  packages, and runtime failure paths; `benchmarks/` holds timing programs.

`make verify` builds the compiler and commands, then runs the suites,
fixtures, and probes. To run selected suites, build with
`make -C unittest test-all`, then run
`(cd unittest && X2C_SCOPE_ACCOUNTING=1 ./test-all string_suite)`.
[STATUS.md](STATUS.md) records known skips and gaps.
