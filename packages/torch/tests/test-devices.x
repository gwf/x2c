/*  test-devices.x -- Device movement and native-to-host copies. */

import "torch" with Torch, Tensor, Module, Optimizer;
#include "test-support.x"
#include <math.h>
$(import "../../../unittest/test-macros.xmacro")

static void devices_cpu(void) {
  $test.scoped();
  Tensor input = Tensor.of(%(1 2 3), %(3), XT_INT64);
  EXPECT_STR_EQ(input.device(), "cpu");
  EXPECT_INT_EQ(input.to_values()[2].integer(), 3);
  Module model = Module.linear(3, 1);
  model.to_device("cpu");
  EXPECT_STR_EQ(model.parameters()[0].tensor().device(), "cpu");
}

static void devices_mps(void) {
  $test.scoped();
  Tensor input = Tensor.of(%((1 2 3) (3 2 1)), %(2 3), XT_FLOAT32)
    .to_device("mps", XT_FLOAT32, 0, 0);
  EXPECT_STR_EQ(input.device(), "mps:0");
  EXPECT_TRUE(fabs(input.to_values()[1].double() - 2.0) < 1e-6);
  Tensor indexes = Tensor.of(%(3 1), %(2), XT_INT64)
    .to_device("mps", XT_INT64, 0, 0);
  EXPECT_INT_EQ(indexes.to_values()[0].integer(), 3);
  EXPECT_TRUE(fabs((2.0 * input).sum().item().double() - 24.0) < 1e-6);
  Module model = Module.linear(3, 1);
  model.to_device("mps");
  Optimizer optimizer = Optimizer.adam(model, 0.01);
  Tensor loss = model.forward(input).square().mean();
  loss.backward();
  optimizer.step();
  model.save("builds/test-mps-model.pt");
  Module copy = Module.linear(3, 1);
  copy.load("builds/test-mps-model.pt");
  EXPECT_TRUE(copy.forward(input.to_device("cpu", XT_FLOAT32, 0, 0))
    .allclose(model.forward(input).to_device("cpu", XT_FLOAT32, 0, 0),
              1e-5, 1e-6));
  int caught = 0;
  try input.to_device("mps", XT_FLOAT64, 0, 0);
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 1);
  Torch.mps_synchronize();
}

void devices_suite(void) {
  $test.run(devices_cpu);
  if (Torch.mps_available()) {
    $test.run(devices_mps);
  }
  else TestHarness_skip("devices_mps", "MPS unavailable on this host");
}
int main(void) {
  TestHarness_begin();
  $test.suite(devices_suite);
  return TestHarness_finish();
}
