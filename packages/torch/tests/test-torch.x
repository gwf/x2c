/*  test-torch.x -- Tensors, operators, autograd, and lifetimes. */

import "torch" with Torch, Tensor;

#include "test-support.x"
#include <math.h>

$(import "../../../unittest/test-macros.xmacro")

#define EXPECT_NEAR(actual, expected, tolerance) \
  EXPECT_TRUE(fabs((actual) - (expected)) < (tolerance))

static void torch_creation_and_queries(void) {
  $test.scoped();
  Tensor m = Tensor.of(%((1 2 3) (4 5 6)), %(2 3), XT_FLOAT64);
  EXPECT_INT_EQ(m.rank(), 2);
  EXPECT_INT_EQ(m.size(1), 3);
  EXPECT_INT_EQ(m.numel(), 6);
  EXPECT_INT_EQ(m.dtype(), XT_FLOAT64);
  EXPECT_STR_EQ(m.shape().str(), "( 2 3 )");
  EXPECT_NEAR(m[1].to_values()[0].double(), 4.0, 1e-12);
  EXPECT_NEAR(m.select(1, 2).sum().item(), 9.0, 1e-12);
  Tensor ones = Tensor.ones(%(2 3), XT_FLOAT32);
  EXPECT_INT_EQ(ones.dtype(), XT_FLOAT32);
  EXPECT_NEAR(ones.to_dtype(XT_FLOAT64).sum().item(), 6.0, 1e-12);
  EXPECT_NEAR(Tensor.arange(0.0, 5.0, 1.0, XT_INT64).sum().item(), 10.0, 1e-12);
  EXPECT_TRUE(Torch.version().len() > 0);
}

static void torch_operators(void) {
  $test.scoped();
  Tensor a = Tensor.of(%(1 2 3 4), %(2 2), XT_FLOAT64);
  Tensor b = Tensor.of(%(1 0 0 1), %(2 2), XT_FLOAT64);
  EXPECT_TRUE((a * b).equal(Tensor.of(%(1 0 0 4), %(2 2), XT_FLOAT64)));
  EXPECT_TRUE((a @ b).equal(a));
  EXPECT_NEAR((a + b - b / 2.0).sum().item(), 10.0 + 2.0 - 1.0, 1e-12);
  EXPECT_NEAR((2.0 * a).sum().item(), 20.0, 1e-12);
  EXPECT_NEAR((-a).sum().item(), -10.0, 1e-12);
  Var boxed = a;
  EXPECT_TRUE(boxed is Tensor);
  EXPECT_NEAR((boxed @ boxed).tensor().to_values()[0].double(), 7.0, 1e-12);
  EXPECT_NEAR(a.t()[0].to_values()[1].double(), 3.0, 1e-12);
  EXPECT_NEAR(a.reshape(%(4)).slice(0, 1, 3, 1).sum().item(), 5.0, 1e-12);
  EXPECT_TRUE(a.tanh().allclose(a.tanh(), 1e-5, 1e-8));
}

static void torch_autograd(void) {
  $test.scoped();
  Tensor w = Tensor.of(%(2 3), %(2), XT_FLOAT64).requires_grad_(1);
  Tensor loss = (w * w).sum();
  loss.backward();
  Array grad = w.grad().to_values();
  EXPECT_NEAR(grad[0].double(), 4.0, 1e-12);
  EXPECT_NEAR(grad[1].double(), 6.0, 1e-12);
  EXPECT_TRUE(Torch.grad_enabled());
  Torch.no_grad();
  EXPECT_FALSE(Torch.grad_enabled());
  w.add_(w.grad(), -0.5);
  Torch.enable_grad();
  EXPECT_NEAR(w.to_values()[0].double(), 0.0, 1e-12);
  EXPECT_FALSE(w.detach().requires_grad());
}

static void torch_errors_and_lifetimes(void) {
  ScopeStats before = Scope.stats();
  Scope.retain();
  {
    defer Scope.release();
    Tensor a = Tensor.ones(%(2 3), XT_FLOAT64);
    Tensor b = Tensor.ones(%(2 2), XT_FLOAT64);
    int caught = 0;
    try {
      Tensor bad = a @ b;
      EXPECT_NULL(bad);
    }
    catch %(bad-state (library "torch") *): caught++;
    EXPECT_INT_EQ(caught, 1);
    try {
      a.grad();
    }
    catch %(bad-state *): caught++;
    EXPECT_INT_EQ(caught, 2);
    Tensor freed = a.free();
    EXPECT_NULL(freed);
    for (int i = 0; i < 100; i++) (void) (b + b);
  }
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
}

void torch_suite(void) {
  $test.run(torch_creation_and_queries);
  $test.run(torch_operators);
  $test.run(torch_autograd);
  $test.run(torch_errors_and_lifetimes);
}

int main(void) {
  TestHarness_begin();
  $test.suite(torch_suite);
  return TestHarness_finish();
}
