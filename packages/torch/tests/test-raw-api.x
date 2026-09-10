/*  test-raw-api.x -- The C ABI in torch-2.10.h is reachable by name. */

import "torch";

#include "test-support.x"

$(import "../../../unittest/test-macros.xmacro")

static void torch_raw_api(void) {
  int64_t shape[2] = { 2, 2 }, count = 0;
  xt_tensor eye = xt_ones(shape, 2, XT_FLOAT64);
  EXPECT_NOT_NULL(eye);
  EXPECT_INT_EQ(xt_numel(eye, &count), 0);
  EXPECT_INT_EQ(count, 4);
  xt_tensor bad = xt_reshape(eye, shape, 1);
  EXPECT_NULL(bad);
  EXPECT_TRUE(String.new(xt_last_error()).len() > 0);
  xt_tensor_free(eye);
}

/* A libtorch throw must become a status, not an unwind across the ABI. */
static void torch_raw_errors_are_statuses(void) {
  int64_t shape[1] = { 2 }, size = 0;
  EXPECT_TRUE(xt_set_num_threads(0) != 0);
  EXPECT_TRUE(String.new(xt_last_error()).len() > 0);
  xt_tensor pair = xt_ones(shape, 1, XT_FLOAT64);
  EXPECT_TRUE(xt_size(pair, 5, &size) != 0);
  xt_tensor_free(pair);
}

void torch_raw_suite(void) {
  $test.run(torch_raw_api);
  $test.run(torch_raw_errors_are_statuses);
}

int main(void) {
  TestHarness_begin();
  $test.suite(torch_raw_suite);
  return TestHarness_finish();
}
