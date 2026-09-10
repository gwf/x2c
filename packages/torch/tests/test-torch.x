/*  test-torch.x -- Tensors, operators, autograd, modules, training,
    checkpoints, and lifetimes. */

import "torch" with Torch, Tensor, Module, Optimizer, Scheduler, Checkpoint;

#include "test-support.x"
#include <math.h>

$(import "../../../unittest/test-macros.xmacro")

#define EXPECT_NEAR(actual, expected, tolerance) \
  EXPECT_TRUE(fabs((actual) - (expected)) < (tolerance))

/* Two Linear children under a composed root; the forward is x2c. */
static Module _mlp(void) {
  Module model = Module.composed();
  model.register("l1", Module.linear(4, 8));
  model.register("l2", Module.linear(8, 1));
  return model;
}

static Tensor _mlp_forward(Module model, Tensor x) {
  Tensor hidden = model.child("l1").forward(x).tanh();
  return model.child("l2").forward(hidden);
}

static void torch_creation_and_queries(void) {
  $test.scoped();
  Tensor m = Tensor.of(%((1 2 3) (4 5 6)), %(2 3), XT_FLOAT64);
  EXPECT_INT_EQ(m.rank(), 2);
  EXPECT_INT_EQ(m.size(1), 3);
  EXPECT_INT_EQ(m.numel(), 6);
  EXPECT_INT_EQ(m.dtype(), XT_FLOAT64);
  EXPECT_STR_EQ(m.shape().str(), "( 2 3 )");
  EXPECT_NEAR(m[1].to_values()[0].double(), 4.0, 1e-12);
  EXPECT_NEAR(m.select(1, 2).sum().item().double(), 9.0, 1e-12);
  Tensor ones = Tensor.ones(%(2 3), XT_FLOAT32);
  EXPECT_INT_EQ(ones.dtype(), XT_FLOAT32);
  EXPECT_NEAR(ones.to_dtype(XT_FLOAT64).sum().item().double(), 6.0, 1e-12);
  EXPECT_INT_EQ(Tensor.arange(0.0, 5.0, 1.0, XT_INT64).sum().item().integer(),
                10);
  EXPECT_TRUE(Torch.version().len() > 0);
}

/* An integer dtype must not lose the value through a double. */
static void torch_integers_are_exact(void) {
  $test.scoped();
  long huge = 9007199254740993;
  Tensor whole = Tensor.of(%($huge), %(1), XT_INT64);
  EXPECT_INT_EQ(whole.item().integer(), huge);
  EXPECT_INT_EQ(whole.to_values()[0].integer(), huge);
  EXPECT_INT_EQ(Tensor.scalar_integer(huge, XT_INT64).item().integer(), huge);
  EXPECT_TRUE(whole.item().is_integer());
  /* 2 converts through long.tensor, so the product stays exact. */
  EXPECT_INT_EQ((whole * 2).item().integer(), huge * 2);
  Tensor real = Tensor.of(%(0.5 1.5), %(2), XT_FLOAT64);
  EXPECT_TRUE(real[0].item().is_floating());
  EXPECT_NEAR(real.sum().item().double(), 2.0, 1e-12);
}

/* A libtorch throw crosses the ABI as an Error, and the process goes on. */
static void torch_errors_reach_x2c(void) {
  $test.scoped();
  int caught = 0;
  EXPECT_TRUE(Torch.num_interop_threads() > 0);
  try { Torch.set_num_threads(0); }
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 1);
  Tensor m = Tensor.ones(%(2 3), XT_FLOAT64);
  try { (void) m.size(5); }
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 2);
  EXPECT_INT_EQ(m.size(1), 3);
}

static void torch_operators(void) {
  $test.scoped();
  Tensor a = Tensor.of(%(1 2 3 4), %(2 2), XT_FLOAT64);
  Tensor b = Tensor.of(%(1 0 0 1), %(2 2), XT_FLOAT64);
  EXPECT_TRUE((a * b).equal(Tensor.of(%(1 0 0 4), %(2 2), XT_FLOAT64)));
  EXPECT_TRUE((a @ b).equal(a));
  EXPECT_NEAR((a + b - b / 2.0).sum().item().double(), 10.0 + 2.0 - 1.0,
              1e-12);
  EXPECT_NEAR((2.0 * a).sum().item().double(), 20.0, 1e-12);
  EXPECT_NEAR((-a).sum().item().double(), -10.0, 1e-12);
  Var boxed = a;
  EXPECT_TRUE(boxed is Tensor);
  EXPECT_NEAR((boxed @ boxed).tensor().to_values()[0].double(), 7.0, 1e-12);
  EXPECT_NEAR(a.t()[0].to_values()[1].double(), 3.0, 1e-12);
  EXPECT_NEAR(a.reshape(%(4)).slice(0, 1, 3, 1).sum().item().double(), 5.0,
              1e-12);
  EXPECT_TRUE(a.tanh().allclose(a.tanh(), 1e-5, 1e-8));
}

static void torch_indexing(void) {
  $test.scoped();
  Tensor m = Tensor.of(%((1 2) (3 4)), %(2 2), XT_FLOAT64);
  /* an integer key selects along dim 0, a List key selects in turn */
  EXPECT_NEAR(m[1].to_values()[0].double(), 3.0, 1e-12);
  EXPECT_NEAR(m[%(1 0)].item().double(), 3.0, 1e-12);
  EXPECT_NEAR(m[%(0 1)].item().double(), 2.0, 1e-12);
  /* a Tensor key is a boolean mask */
  Tensor mask = m.gt(Tensor.scalar(2.0, XT_FLOAT64));
  EXPECT_INT_EQ(mask.dtype(), XT_BOOL);
  Tensor large = m[mask];
  EXPECT_INT_EQ(large.numel(), 2);
  EXPECT_NEAR(large.sum().item().double(), 7.0, 1e-12);
  EXPECT_NEAR(m.masked_select(mask).sum().item().double(), 7.0, 1e-12);
  Tensor picked = Tensor.where(mask, m, Tensor.scalar(0.0, XT_FLOAT64));
  EXPECT_NEAR(picked.sum().item().double(), 7.0, 1e-12);
  EXPECT_NEAR(m.narrow(0, 1, 1).sum().item().double(), 7.0, 1e-12);
  EXPECT_INT_EQ(m.flatten(0, 1).rank(), 1);
  EXPECT_INT_EQ(m.argmax(1, 0).to_values()[0].integer(), 1);
  EXPECT_NEAR(m.max().item().double(), 4.0, 1e-12);
  EXPECT_NEAR(m.min().item().double(), 1.0, 1e-12);
  EXPECT_NEAR(Tensor.cat(%($m $m), 0).sum().item().double(), 20.0, 1e-12);
  EXPECT_INT_EQ(Tensor.stack(%($m $m), 0).rank(), 3);
  EXPECT_NEAR(m.softmax(1).sum().item().double(), 2.0, 1e-12);
  EXPECT_INT_EQ(m.eq(m).sum().item().integer(), 4);
  Tensor order = Torch.randperm(6);
  EXPECT_INT_EQ(order.numel(), 6);
  EXPECT_INT_EQ(order.sum().item().integer(), 15);
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
  Scope.retain();
  {
    defer Scope.release();
    Torch.no_grad();
    EXPECT_FALSE(Torch.grad_enabled());
    w.add_(w.grad(), -0.5);
  }
  EXPECT_TRUE(Torch.grad_enabled());
  EXPECT_NEAR(w.to_values()[0].double(), 0.0, 1e-12);
  EXPECT_FALSE(w.detach().requires_grad());
}

/* The grad mode is tied to a scope, so nesting restores in order and an
   Error leaving a no-grad scope still restores. */
static void torch_no_grad_is_scoped(void) {
  $test.scoped();
  EXPECT_TRUE(Torch.grad_enabled());
  Scope.retain();
  {
    defer Scope.release();
    Torch.no_grad();
    EXPECT_FALSE(Torch.grad_enabled());
    Scope.retain();
    {
      defer Scope.release();
      Torch.no_grad();
      EXPECT_FALSE(Torch.grad_enabled());
    }
    EXPECT_FALSE(Torch.grad_enabled());
  }
  EXPECT_TRUE(Torch.grad_enabled());

  int caught = 0;
  try {
    Scope.retain();
    defer Scope.release();
    Torch.no_grad();
    EXPECT_FALSE(Torch.grad_enabled());
    Tensor a = Tensor.ones(%(2 3), XT_FLOAT64);
    Tensor b = Tensor.ones(%(2 2), XT_FLOAT64);
    (void) (a @ b);
  }
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_TRUE(Torch.grad_enabled());

  Scope.retain();
  {
    defer Scope.release();
    Torch.inference_mode();
    EXPECT_FALSE(Torch.grad_enabled());
  }
  EXPECT_TRUE(Torch.grad_enabled());
}

static void torch_modules(void) {
  $test.scoped();
  Torch.manual_seed(3);
  Module layer = Module.linear(3, 2);
  Tensor x = Tensor.of(%((1 2 3)), %(1 3), XT_FLOAT32);
  Tensor weight = layer.named_parameters()[0].list()[1].tensor();
  Tensor bias = layer.named_parameters()[1].list()[1].tensor();
  EXPECT_STR_EQ(layer.named_parameters()[0].list()[0].str(), "weight");
  EXPECT_TRUE(layer.forward(x).allclose(x @ weight.t() + bias, 1e-5, 1e-6));

  Module model = _mlp();
  List names = %();
  foreach (List pair, model.named_parameters()) {
    String name = pair[0].str();
    names = names.append(%($name));
  }
  EXPECT_INT_EQ(model.parameters().len(), 4);
  EXPECT_STR_EQ(names.str(), "( l1.weight l1.bias l2.weight l2.bias )");
  EXPECT_INT_EQ(model.buffers().len(), 0);
  EXPECT_TRUE(model.is_training());
  model.eval();
  EXPECT_FALSE(model.is_training());
  EXPECT_FALSE(model.child("l1").is_training());
  model.train();
  EXPECT_TRUE(model.is_training());

  int caught = 0;
  try { model.forward(x); }
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 1);
  try { model.child("l3"); }
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 2);
}

static void torch_optimizers(void) {
  $test.scoped();
  Torch.manual_seed(11);
  /* One SGD step is the manual update, to float32 tolerance. */
  Module layer = Module.linear(2, 1);
  Tensor weight = layer.parameters()[0].tensor();
  Tensor x = Tensor.of(%((1 2)), %(1 2), XT_FLOAT32);
  Tensor before = weight.detach().clone();
  Tensor loss = layer.forward(x).sum();
  loss.backward();
  Tensor expected = before + weight.grad().detach() * -0.1;
  Optimizer sgd = Optimizer.sgd(layer, 0.1);
  sgd.step();
  EXPECT_TRUE(weight.detach().allclose(expected, 1e-5, 1e-7));
  EXPECT_NEAR(sgd.lr(), 0.1, 1e-12);
  sgd.set_lr(0.25);
  EXPECT_NEAR(sgd.lr(), 0.25, 1e-12);

  /* Adam reduces a fixed problem's loss over 50 steps. */
  Torch.manual_seed(0);
  Module model = _mlp();
  Tensor data = Tensor.randn(%(16 4), XT_FLOAT32);
  Tensor target = data.sum_dim(1, 1);
  Optimizer adam = Optimizer.adam(model, 0.05);
  double first = 0.0, last = 0.0;
  for (int step = 0; step < 50; step++) {
    Scope.retain();
    {
      defer Scope.release();
      adam.zero_grad();
      Tensor error = Tensor.mse_loss(_mlp_forward(model, data), target);
      error.backward();
      adam.step();
      last = error.item().double();
      if (!step) first = last;
    }
  }
  EXPECT_TRUE(last < first * 0.1);

  /* Optimizer state round-trips through the C++ archive: resuming from a
     saved state and the saved parameters gives the same next step. */
  adam.save("builds/test-optim.pt");
  model.save("builds/test-resume.pt");
  Scope.retain();
  {
    defer Scope.release();
    adam.zero_grad();
    Tensor error = Tensor.mse_loss(_mlp_forward(model, data), target);
    error.backward();
    adam.step();
  }
  Tensor direct = model.parameters()[0].tensor().detach().clone();

  model.load("builds/test-resume.pt");
  Optimizer resumed = Optimizer.adam(model, 0.05);
  resumed.load("builds/test-optim.pt");
  Scope.retain();
  {
    defer Scope.release();
    resumed.zero_grad();
    Tensor error = Tensor.mse_loss(_mlp_forward(model, data), target);
    error.backward();
    resumed.step();
  }
  EXPECT_TRUE(model.parameters()[0].tensor().detach()
              .allclose(direct, 1e-6, 1e-8));
}

static void torch_schedulers(void) {
  $test.scoped();
  Module layer = Module.linear(2, 1);
  Optimizer sgd = Optimizer.sgd(layer, 1.0);
  Scheduler halve = Scheduler.step_lr(sgd, 2, 0.5);
  /* StepLR counts its own calls: the first two leave the rate alone and
     the one that completes the second period halves it. */
  halve.step();
  EXPECT_NEAR(sgd.lr(), 1.0, 1e-12);
  halve.step();
  EXPECT_NEAR(sgd.lr(), 1.0, 1e-12);
  halve.step();
  EXPECT_NEAR(sgd.lr(), 0.5, 1e-12);

  Optimizer other = Optimizer.sgd(layer, 1.0);
  Scheduler plateau = Scheduler.reduce_on_plateau(other, 1, 0.5, 1, 1e-4, 0,
                                                  0.0);
  for (int i = 0; i < 4; i++) plateau.step_metric(1.0);
  EXPECT_TRUE(other.lr() < 1.0);
  int caught = 0;
  try { plateau.step(); }
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 1);
}

static void torch_checkpoints(void) {
  $test.scoped();
  Torch.manual_seed(5);
  Module model = _mlp();
  Tensor x = Tensor.randn(%(4 4), XT_FLOAT32);
  Tensor before = _mlp_forward(model, x).detach().clone();
  model.save("builds/test-model.pt");

  Module fresh = _mlp();
  EXPECT_FALSE(_mlp_forward(fresh, x).detach().allclose(before, 1e-5, 1e-7));
  fresh.load("builds/test-model.pt");
  EXPECT_TRUE(_mlp_forward(fresh, x).detach().allclose(before, 1e-6, 1e-8));

  model.save_archive("builds/test-model-archive.pt");
  Module third = _mlp();
  third.load_archive("builds/test-model-archive.pt");
  EXPECT_TRUE(_mlp_forward(third, x).detach().allclose(before, 1e-6, 1e-8));

  /* A checkpoint missing a parameter name is a clear failure. */
  Map partial = %{};
  partial["l1.weight"] = model.parameters()[0].tensor();
  Checkpoint.save(partial, "builds/test-partial.pt");
  int caught = 0;
  try { fresh.load("builds/test-partial.pt"); }
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 1);

  Map pair = %{};
  pair["a"] = Tensor.of(%(1 2 3), %(3), XT_FLOAT64);
  pair["b"] = Tensor.of(%(4 5), %(2), XT_INT64);
  Checkpoint.save(pair, "builds/test-pair.pt");
  Map read = Checkpoint.load("builds/test-pair.pt");
  EXPECT_INT_EQ(read.len(), 2);
  EXPECT_NEAR(read["a"].tensor().sum().item().double(), 6.0, 1e-12);
  EXPECT_INT_EQ(read["b"].tensor().sum().item().integer(), 9);
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

    Module model = _mlp();
    Optimizer adam = Optimizer.adam(model, 0.01);
    Scheduler schedule = Scheduler.step_lr(adam, 1, 0.5);
    schedule.step();
    EXPECT_NULL(schedule.free());
    EXPECT_NULL(adam.free());
    EXPECT_NULL(model.free());
    for (int i = 0; i < 10; i++) {
      Module extra = _mlp();
      (void) Optimizer.adam(extra, 0.01);
    }
  }
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
}

static void torch_shapes_reject_symbols(void) {
  $test.scoped();
  // A bare name inside %() is a Symbol, never a number; a shape or index
  // built from one must raise instead of reading the Symbol's payload.
  int caught = 0;
  try Tensor.of(%(1 2), %(rows 2), XT_INT64);
  catch %(no-convert *): caught++;
  try Tensor.zeros(%(3 cols), XT_FLOAT64);
  catch %(no-convert *): caught++;
  Tensor t = Tensor.arange(0.0, 6.0, 1.0, XT_FLOAT64).reshape(%(2 3));
  try t[%(first 1)];
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 3);
  EXPECT_INT_EQ(t.numel(), 6);
}

void torch_suite(void) {
  $test.run(torch_shapes_reject_symbols);
  $test.run(torch_creation_and_queries);
  $test.run(torch_integers_are_exact);
  $test.run(torch_errors_reach_x2c);
  $test.run(torch_operators);
  $test.run(torch_indexing);
  $test.run(torch_autograd);
  $test.run(torch_no_grad_is_scoped);
  $test.run(torch_modules);
  $test.run(torch_optimizers);
  $test.run(torch_schedulers);
  $test.run(torch_checkpoints);
  $test.run(torch_errors_and_lifetimes);
}

int main(void) {
  TestHarness_begin();
  $test.suite(torch_suite);
  return TestHarness_finish();
}
