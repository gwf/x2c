/*  test-test.x -- user test registration, selection, and reports */

#include "test.x"
#include "test-support.x"
#include "test-macros.x"

$test()
static void user_pass(void) {
  int value = 0;
  $expect(++value == 1);
  $expect_eq(++value, 2);
  $expect_eq("same", "same");
  Symbol actual = <bad-arg>, expected = <bad-state>;
  $expect_raises(actual, { raise %(bad-arg (expected $expected)); });
}

$test()
static void user_fail(void) {
  $expect(0);
  $expect_eq("first\nactual\n", "first\nexpected\n");
  $expect_raises(<bad-arg>, { (void) 0; });
  $expect_raises(<bad-arg>, { raise %(bad-state); });
}

$test()
static void user_error(void) { raise %(bad-arg); }

$test()
static void user_skip(void) { Test.skip("not available"); }

static String long_skip_reason(void) {
  Buffer reason = auto Buffer.new(0);
  for (int i = 0; i < 20; i++)
    reason.printf("dynamic-%02d-abcdefghijklmnop;", i);
  return reason;
}

$test()
static void user_long_skip(void) { Test.skip(long_skip_reason()); }

$test()
static void user_after_long_skip(void) { $expect(1); }

$test()
static void user_failed_skip(void) { $expect(0); Test.skip("failure remains"); }

$test()
static void user_empty_skip(void) { Test.skip(""); $expect(0); }

$test()
static void user_no_error_zero(void) {
  $expect_raises(0, { (void) 0; });
}

static String run_tests(List arguments, int &status) {
  File saved = Stdout, output = tmpfile();
  defer output.close();
  Stdout = output;
  defer Stdout = saved;
  int argc = arguments.len();
  char **argv = xcalloc(argc + 1, sizeof(char *));
  defer xfree(argv);
  for (int i = 0; i < argc; i++) argv[i] = arguments[i];
  status = Test.main(argc, argv);
  output.flush();
  long length = output.tell();
  output.seek(0, SEEK_SET);
  return output.readblock(length);
}

static void user_test_assertions_and_errors(void) {
  $test.scoped();
  int status;
  String output = run_tests(%("test" "--filter" "user_pass"), status);
  EXPECT_INT_EQ(status, 0);
  EXPECT_STR_EQ(output, "ok user_pass\n1 passed, 0 failed, 0 skipped\n");
  output = run_tests(%("test" "--filter" "user_fail"), status);
  EXPECT_INT_EQ(status, 1);
  EXPECT_TRUE(output.contains("FAIL user_fail"));
  EXPECT_TRUE(output.contains("expected 0"));
  EXPECT_TRUE(output.contains("--- expected\n+++ actual\n"));
  EXPECT_TRUE(output.contains("-expected\n+actual\n"));
  EXPECT_TRUE(output.contains("1 passed") == 0);
  output = run_tests(%("test" "--filter" "user_error"), status);
  EXPECT_INT_EQ(status, 1);
  EXPECT_TRUE(output.contains("uncaught Error <bad-arg>"));
}

static void user_test_selection_and_skip(void) {
  $test.scoped();
  int status;
  String output = run_tests(
    %("test" "--filter" "user_pass" "--filter" "user_skip" "--quiet"), status);
  EXPECT_INT_EQ(status, 0);
  EXPECT_STR_EQ(output,
    "skip user_skip: not available\n1 passed, 0 failed, 1 skipped\n");
  output = run_tests(%("test" "--filter" "absent"), status);
  EXPECT_INT_EQ(status, 2);
  EXPECT_STR_EQ(output, "0 passed, 0 failed, 0 skipped\n");
  output = run_tests(%("test" "--list" "--filter" "user_"), status);
  EXPECT_INT_EQ(status, 0);
  EXPECT_STR_EQ(output,
    "user_pass\nuser_fail\nuser_error\nuser_skip\n"
    "user_long_skip\nuser_after_long_skip\nuser_failed_skip\n"
    "user_empty_skip\nuser_no_error_zero\n");
  output = run_tests(%("test" "--filter" "user_empty_skip"), status);
  EXPECT_INT_EQ(status, 0);
  EXPECT_TRUE(output.contains("0 passed, 0 failed, 1 skipped"));
  output = run_tests(%("test" "--filter" "user_no_error_zero"), status);
  EXPECT_INT_EQ(status, 1);
  EXPECT_TRUE(output.contains("expected Error to be raised"));
  output = run_tests(%("test" "--list" "--filter" "absent"), status);
  EXPECT_INT_EQ(status, 2);
  EXPECT_STR_EQ(output, "0 passed, 0 failed, 0 skipped\n");
  output = run_tests(%("test"), status);
  EXPECT_INT_EQ(status, 1);
  EXPECT_TRUE(output.endswith("2 passed, 4 failed, 3 skipped\n"));
}

static void user_test_skip_reason_survives_catch(void) {
  $test.scoped();
  String reason = long_skip_reason();
  int status;
  String output = run_tests(%("test" "--filter" "long_skip"), status);
  EXPECT_INT_EQ(status, 0);
  String expected = %"skip user_long_skip: $reason\n" +
    "ok user_after_long_skip\n1 passed, 0 failed, 1 skipped\n";
  EXPECT_STR_EQ(output, expected);
  output = run_tests(%("test" "--filter" "user_failed_skip"), status);
  EXPECT_INT_EQ(status, 1);
  EXPECT_TRUE(output.contains("FAIL user_failed_skip"));
  EXPECT_TRUE(output.contains("expected 0"));
  EXPECT_TRUE(output.endswith("0 passed, 1 failed, 0 skipped\n"));
}

void test_suite(void) {
  $test.run(user_test_assertions_and_errors);
  $test.run(user_test_selection_and_skip);
  $test.run(user_test_skip_reason_survives_catch);
}
