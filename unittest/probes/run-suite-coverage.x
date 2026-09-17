#!/usr/bin/env -S x2c script
/*  run-suite-coverage.x -- every test-*.x file must be a registered suite

    Discovery (unittest/test-*.x) and execution (the $test.suite calls in
    test-all.x) can drift: a new test-foo.x compiles and links but is never
    called. The counts must match. test-all.x and test-support.x are the
    driver and shared support, not suites. Run from the repository root.
*/
List exceptions = %("test-all.x" "test-support.x");
int files = 0;
foreach (Path source, Path.glob("unittest/test-*.x"))
  if (!exceptions.contains(source.basename().str())) files++;
int suites = Path.read_text("unittest/test-all.x").count("$test.suite(");
if (files != suites) {
  Stderr.printf("suite coverage mismatch: %d discoverable test-*.x files "
                "(excluding test-all.x, test-support.x) but %d $test.suite "
                "calls in test-all.x main\n", files, suites);
  Stderr.printf("a test-*.x file was added or removed without updating "
                "test-all.x, or an exception needs to be added to "
                "unittest/probes/run-suite-coverage.x\n");
  return 1;
}
printf("suite coverage: %d test files match %d suite calls in test-all.x\n",
       files, suites);
