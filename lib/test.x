/*  test.x -- registered tests and assertions for user programs

    Copyright (c) 2026 Gary William Flake
*/

#pragma once
#include "diff.x"
#include "system-macros.x"

/** The receiverless owner of registered tests and their assertions. */
typedef Symbol Test;

/** A registered test has no arguments and returns no value. */
typedef void (*TestFunction)(void);

static List _tests, _failures;
static String _skipped;
static int _did_skip;

/** Registers a function, its name, and the location of its decoration.
    `$test` calls this before main, preserving declaration order.
*/
void Test.register(
  const char *name, TestFunction function, const char *file, int line) {
  String name_text = name, file_text = file;
  _tests = cons($(name_text, (long) function, file_text, line), _tests);
}

/** Records a failed condition with its source text and location. */
void Test.check(int condition, String expression, String file, int line) {
  if (!condition)
    _failures = cons(%"$(file):$(line): expected $(expression)", _failures);
}

/** Compares boxed values and records their representations on failure.
    Two differing multiline Strings also produce a unified difference.
*/
void Test.compare(Var actual, Var expected, String file, int line) {
  if (actual.equal(expected)) return;
  String message = %"$(file):$(line): actual $(actual.repr()), " +
    %"expected $(expected.repr())";
  if (actual is <string> && expected is <string>) {
    String a = actual, b = expected;
    if (a.contains("\n") && b.contains("\n"))
      message += "\n" + Diff.unified(b, a, "expected", "actual");
  }
  _failures = cons(message, _failures);
}

/** Marks the running test skipped and stops its body. */
void Test.skip(String reason) {
  raise %(test-skip (reason $reason));
}

/** Runs registered tests, returning 1 on failure or 2 for an unmatched
    filter. `--filter TEXT` is repeatable and selects names containing any
    filter; `--list` prints selected names; `--quiet` omits passing lines.
*/
int Test.main(int argc, char **argv) {
  List filters = NULL;
  int list = 0, quiet = 0;
  for (int i = 1; i < argc; i++) {
    String arg = argv[i];
    if (arg == "--filter" && i + 1 < argc) {
      String filter = argv[++i];
      filters = cons(filter, filters);
    }
    else if (arg == "--list") list = 1;
    else if (arg == "--quiet") quiet = 1;
    else {
      Stderr.printf("test: unknown or incomplete option %s\n", arg);
      return 2;
    }
  }
  int passed = 0, failed = 0, skipped = 0, matched = 0;
  foreach (List row in _tests.reverse()) {
    (String name, long function, String file, int line) = row;
    if (!_selected(name, filters)) continue;
    matched++;
    if (list) { Stdout.printf("%s\n", name); continue; }
    _run((TestFunction) function);
    if (_failures) {
      failed++;
      Stdout.printf("FAIL %s (%s:%d)\n", name, file, line);
      foreach (String failure in _failures.reverse())
        Stdout.printf("  %s\n", failure);
    }
    else if (_did_skip) {
      skipped++;
      Stdout.printf("skip %s: %s\n", name, _skipped ? _skipped : "");
    }
    else {
      passed++;
      if (!quiet) Stdout.printf("ok %s\n", name);
    }
  }
  if (!list || (filters && !matched))
    Stdout.printf(
      "%d passed, %d failed, %d skipped\n", passed, failed, skipped);
  return failed ? 1 : filters && !matched ? 2 : 0;
}

static int _selected(String name, List filters) {
  if (!filters) return 1;
  foreach (String filter in filters) if (name.contains(filter)) return 1;
  return 0;
}

static void _run(TestFunction function) {
  _failures = NULL, _skipped = NULL, _did_skip = 0;
  try function();
  catch %(test-skip (reason ?reason)): {
    _skipped = Error.snapshot(reason);
    _did_skip = 1;
  }
  catch %(?cause *detail):
    _failures = cons(
      %"uncaught Error $(cause.repr()): $(detail.repr())", _failures);
}

/** Keeps a decorated test and registers it at unit initialization. */
meta List test_register(List function) {
  String name = Code.name(function);
  List target = x2c_ident(name);
  String file = x2c_invocation_file();
  int line = x2c_invocation_line();
  x2c_place(
    %(unit-init), $!{
    Test.register($name, $target, $file, $line);
  });
  return $(function);
}

/** Decorates a `static void name(void)` function as a test. */
macro Decorator $test(Unit $function) { @test_register($function) }

/** Records a failed condition without stopping the test. */
macro Stmt $expect(Expr $condition) {
  Test.check(
    $condition, $_macros_source($condition),
    $x2c_invocation_file(), $x2c_invocation_line());
}

/** Evaluates each value once and compares them with `Var.equal`. */
macro Stmt $expect_eq(Expr $actual, Expr $expected) {
  Test.compare(
    $actual, $expected, $x2c_invocation_file(), $x2c_invocation_line());
}

/** Records a failure unless the statement raises the requested cause. */
macro Stmt $expect_raises(Expr $cause, Stmt $statement) {
  using $expected, $actual, $raised;
  {
    Symbol $expected = $cause, $actual = 0;
    int $raised = 0;
    try $statement
    catch %(?caught *detail): { $actual = caught; $raised = 1; }
    Test.check(
      $raised, "Error to be raised",
      $x2c_invocation_file(), $x2c_invocation_line());
    if ($raised) Test.compare(
      $actual, $expected, $x2c_invocation_file(), $x2c_invocation_line());
  }
}

/** Writes the entry point for a complete test program. */
macro Unit $test.main() {
  int $x2c_ident("main")(int argc, char **argv) => Test.main(argc, argv);
}
