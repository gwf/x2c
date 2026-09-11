/*  test-custom.x -- Custom gradients, callback lifetime and error transfer. */

import "torch" with Torch, Tensor, AutogradContext;
#include "test-support.x"
#include <math.h>
#include <pthread.h>
$(import "../../../unittest/test-macros.xmacro")

static pthread_t caller;
static int calls;

static Tensor _product(AutogradContext context, List inputs) {
  EXPECT_TRUE(pthread_equal(caller, pthread_self()));
  calls++;
  Tensor x = inputs[0].tensor(), y = inputs[1].tensor();
  context.save_for_backward(%($x $y));
  return x * y;
}

static List _product_gradient(AutogradContext context, Tensor gradient) {
  EXPECT_TRUE(pthread_equal(caller, pthread_self()));
  EXPECT_TRUE(context.needs_input_grad(0));
  EXPECT_TRUE(context.needs_input_grad(1));
  calls++;
  List saved = context.saved_tensors();
  Tensor dx = gradient * saved[1].tensor();
  Tensor dy = gradient * saved[0].tensor();
  return %($dx $dy);
}

static Tensor _fail_forward(AutogradContext context, List inputs) {
  raise %(bad-arg (reason "forward callback"));
}

static List _fail_backward(AutogradContext context, Tensor gradient) {
  raise %(bad-arg (reason "backward callback"));
}

static List _nested_backward(AutogradContext context, Tensor gradient) {
  gradient.backward_callbacks();
  return %();
}

static Tensor _mutate(AutogradContext context, List inputs) {
  Tensor input = inputs[0].tensor();
  input.add_(input, 1.0);
  return input.square();
}

static List _selected_gradient(AutogradContext context, Tensor gradient) {
  EXPECT_TRUE(!context.needs_input_grad(0));
  EXPECT_TRUE(context.needs_input_grad(1));
  Tensor input = context.saved_tensors()[0].tensor();
  Tensor result = gradient * input;
  return %( ${Var.null()} $result );
}

static void *_other_thread(void *tensor) {
  return (void *) (long) xt_backward_callbacks(tensor);
}

static void _device(String device) {
  Tensor x = Tensor.of(%(2 3), %(2), XT_FLOAT32)
    .to_device(device, XT_FLOAT32, 0, 0).requires_grad_(1);
  Tensor y = Tensor.of(%(5 7), %(2), XT_FLOAT32)
    .to_device(device, XT_FLOAT32, 0, 0).requires_grad_(1);
  Tensor output = Tensor.custom(_product, _product_gradient, %($x $y));
  output.sum().backward_callbacks();
  EXPECT_TRUE(x.grad().equal(y));
  EXPECT_TRUE(y.grad().equal(x));
  int caught = 0;
  try Tensor.custom(_fail_forward, _product_gradient, %($x $y));
  catch %(bad-arg (reason "forward callback")): caught++;
  Tensor failure = Tensor.custom(_product, _fail_backward, %($x $y));
  try failure.sum().backward_callbacks();
  catch %(bad-arg (reason "backward callback")): caught++;
  Tensor nested = Tensor.custom(_product, _nested_backward, %($x $y));
  try nested.sum().backward_callbacks();
  catch %(bad-state (library "torch") *): caught++;
  Tensor wrong = Tensor.custom(_product, _product_gradient, %($x $y));
  try wrong.sum().backward();
  catch %(bad-state (library "torch") *): caught++;
  try Tensor.custom(_mutate, _product_gradient, %($x $y));
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 5);
  Tensor selected = Tensor.custom(_product, _selected_gradient,
                                   %( ${x.detach()} $y ));
  selected.sum().backward_callbacks();
  Tensor remote = Tensor.custom(_product, _product_gradient, %($x $y));
  Tensor total = remote.sum();
  pthread_t thread;
  void *status;
  EXPECT_INT_EQ(pthread_create(&thread, NULL, _other_thread, total.native()),
                0);
  EXPECT_INT_EQ(pthread_join(thread, &status), 0);
  EXPECT_TRUE((long) status != 0);
  EXPECT_TRUE(Torch.grad_enabled());
  x.zero_grad();
  x.square().sum().backward();
  EXPECT_TRUE(x.grad().allclose(x * 2, 1e-6, 1e-6));
  {
    Scope.retain();
    defer Scope.release();
    Torch.inference_mode();
    Tensor a = Tensor.ones(%(2), XT_FLOAT32)
      .to_device(device, XT_FLOAT32, 0, 0);
    Tensor b = a * 3;
    Tensor prediction = Tensor.custom(_product, _product_gradient, %($a $b));
    EXPECT_TRUE(prediction.equal(b));
    EXPECT_TRUE(!prediction.requires_grad());
    int rejected = 0;
    try Tensor.custom(_mutate, _product_gradient, %($x $y));
    catch %(bad-state (library "torch") *): rejected = 1;
    EXPECT_TRUE(rejected);
  }
  EXPECT_TRUE(Torch.grad_enabled());
}

static void custom_gradients(void) {
  $test.scoped();
  caller = pthread_self();
  _device("cpu");
  if (Torch.mps_available()) _device("mps");
  EXPECT_TRUE(calls >= 5);
}

void custom_suite(void) { $test.run(custom_gradients); }
int main(void) {
  TestHarness_begin();
  $test.suite(custom_suite);
  return TestHarness_finish();
}
