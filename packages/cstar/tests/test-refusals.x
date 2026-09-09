/* test-refusals.x -- what cstar-verify refuses, and where it says so. */

import "cstar" with Cstar;

#include "test-support.x"
#include <stdlib.h>

$(import "../../../unittest/test-macros.xmacro")

static String refuse(String input) {
  String errors = %"builds/refuse.err";
  int status = system(
    %"./builds/cstar-verify --emit ${input} >builds/refuse.out 2>${errors}");
  EXPECT_INT_EQ(WEXITSTATUS(status), 2);
  File captured = File.open(errors, %"r");
  EXPECT_NOT_NULL(captured);
  defer captured.close();
  return captured.string();
}

static void an_outer_decorator_invalidates_the_record(void) {
  String reported = refuse(%"tests/outer-decorator.x");
  EXPECT_TRUE(reported.find(%"outermost decorator") >= 0);
  EXPECT_TRUE(reported.find(%"recorded for identity") >= 0);
}

static void an_unsupported_statement_names_its_location(void) {
  String reported = refuse(%"tests/unsupported.x");
  EXPECT_TRUE(reported.find(%"unsupported: statement") >= 0);
  EXPECT_TRUE(reported.find(%"tests/unsupported.x:12") >= 0);
}

static void a_file_without_annotations_is_not_verified(void) {
  String reported = refuse(%"tests/plain.x");
  EXPECT_TRUE(reported.find(%"no cstar annotations") >= 0);
}

static void refusal_suite(void) {
  $test.run(an_outer_decorator_invalidates_the_record);
  $test.run(an_unsupported_statement_names_its_location);
  $test.run(a_file_without_annotations_is_not_verified);
}

int main(void) {
  TestHarness_begin();
  $test.suite(refusal_suite);
  return TestHarness_finish();
}
