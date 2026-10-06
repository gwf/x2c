/*  test-errors.x -- package error payloads and macro insertion sites */

import "libuv" with UvTcp;

#include "meta.x"
#include "test-support.x"


#include "../src/libuv-errors.x"
#include "../../../unittest/test-macros.x"

static List seen_detail, seen_location;
static Symbol seen_cause;
static int evaluations, evaluation_order;

static Symbol _observe(List errors, Var value) {
  (void) value;
  List error = errors[0];
  seen_cause = error.assoc(<code>);
  seen_detail = Error.snapshot(error.assoc(<detail>));
  seen_location = Error.snapshot(error.assoc(<location>));
  return <declined>;
}

static String _operand(int mark, String value) {
  evaluations++;
  evaluation_order = evaluation_order * 10 + mark;
  return value;
}

static int _direct(void) {
  int status = -1;
  raise %(io-fail (library "libuv") (operation ${_operand(1, "write")})
          (status $status) (name ${_operand(2, "UV_EPERM")})
          (message ${_operand(3, "not permitted")}));
}

static int _catalogue(void) {
  $error.native.status(_operand(1, "write"), -1,
    _operand(2, "UV_EPERM"), _operand(3, "not permitted"));
}

static void payloads_and_expression_occurrences_match(void) {
  evaluations = evaluation_order = 0;
  try {
    ErrorHandler observer = Error.push(_observe, void);
    defer Error.pop(observer);
    _direct();
  }
  catch %(io-fail *): {}
  List original = seen_detail;
  int original_order = evaluation_order;
  EXPECT_INT_EQ(evaluations, 3);
  EXPECT_STR_EQ(seen_location.assoc(<function>).string(), "_direct");

  evaluations = evaluation_order = 0;
  try {
    ErrorHandler observer = Error.push(_observe, void);
    defer Error.pop(observer);
    _catalogue();
  }
  catch %(io-fail *): {}
  EXPECT_INT_EQ(evaluations, 3);
  EXPECT_LIST_EQ(seen_detail, original);
  EXPECT_INT_EQ(evaluation_order, original_order);
  EXPECT_TRUE(seen_cause == <io-fail>);
  EXPECT_STR_EQ(seen_location.assoc(<function>).string(), "_catalogue");
}

static void omitted_fields_and_nonreturning_statements_remain(void) {
  int reached = 0;
  try {
    ErrorHandler observer = Error.push(_observe, void);
    defer Error.pop(observer);
    if (1) $error.address.length();
    reached = 1;
  }
  catch %(size-limit (library "libuv")): {}
  EXPECT_INT_EQ(reached, 0);
  EXPECT_INT_EQ(seen_detail.len(), 1);
  EXPECT_STR_EQ(seen_location.assoc(<function>).string(),
    "omitted_fields_and_nonreturning_statements_remain");
  EXPECT_TRUE(seen_location.assoc(<line>).integer() > 0);
}

static void package_helpers_keep_their_location(void) {
  int caught = 0;
  try {
    ErrorHandler observer = Error.push(_observe, void);
    defer Error.pop(observer);
    UvTcp.bind(NULL, NULL, 0);
  }
  catch %(bad-arg (library "libuv") (operation "tcp_bind")
    (reason "a TCP handle is required")): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_STR_EQ(seen_location.assoc(<function>).string(), "_uv_tcp_ready");
  EXPECT_STR_EQ(seen_location.assoc(<file>).string(), "src/libuv.x");
}

static void error_suite(void) {
  $test.run(payloads_and_expression_occurrences_match);
  $test.run(omitted_fields_and_nonreturning_statements_remain);
  $test.run(package_helpers_keep_their_location);
}

int main(void) {
  TestHarness_begin();
  $test.suite(error_suite);
  return TestHarness_finish();
}
