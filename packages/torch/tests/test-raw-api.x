/*  test-raw-api.x -- The C ABI in torch-2.10.h is reachable by name. */

import "torch";

#include "test-support.x"

$(import "../../../unittest/test-macros.xmacro")

static void torch_raw_api(void) {
  int64_t shape[2] = { 2, 2 };
  xt_tensor eye = xt_ones(shape, 2, XT_FLOAT64);
  EXPECT_NOT_NULL(eye);
  EXPECT_INT_EQ(xt_numel(eye), 4);
  xt_tensor bad = xt_reshape(eye, shape, 1);
  EXPECT_NULL(bad);
  EXPECT_TRUE(String.new(xt_last_error()).len() > 0);
  xt_tensor_free(eye);
}

void torch_raw_suite(void) {
  $test.run(torch_raw_api);
}

int main(void) {
  TestHarness_begin();
  $test.suite(torch_raw_suite);
  return TestHarness_finish();
}
