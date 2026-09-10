/*  checkpoint-roundtrip.x -- The x2c half of tests/verify-python.py.

    With no argument it seeds libtorch, writes the initial parameters and
    the data to builds/x2c-init.pt, trains 20 Adam steps, writes
    builds/x2c-model.pt, and prints the resulting loss. With `load` it
    reads builds/python-model.pt into a fresh model and prints that
    model's loss on the same data.
*/

import "torch" with Torch, Tensor, Module, Optimizer, Checkpoint;

#include <string.h>

#define STEPS 20
#define LR 0.05

static Module _mlp(void) {
  Module model = Module.composed();
  model.register("l1", Module.linear(4, 8));
  model.register("l2", Module.linear(8, 1));
  return model;
}

static Tensor _affine(Module layer, Tensor x) {
  List parameters = layer.parameters();
  Tensor weight = parameters[0].tensor(), bias = parameters[1].tensor();
  return x @ weight.t() + bias;
}

static Tensor _forward(Module model, Tensor x) =>
  _affine(model.child("l2"), _affine(model.child("l1"), x).tanh());

static double _loss(Module model, Tensor x, Tensor y) {
  Scope.retain();
  defer Scope.release();
  Torch.no_grad();
  return Tensor.mse_loss(_forward(model, x), y).item().double();
}

static int _train(void) {
  Torch.manual_seed(0);
  Tensor x = Tensor.randn(%(64 4), XT_FLOAT32);
  Tensor weights = Tensor.of(%(0.5 -1.25 2.0 0.75), %(1 4), XT_FLOAT32);
  Tensor y = x @ weights.t() + 0.5 + Tensor.randn(%(64 1), XT_FLOAT32) * 0.05;

  Module model = _mlp();
  Map start = %{};
  foreach (List pair, model.named_parameters())
    start[pair[0].str()] = pair[1].tensor();
  start["data.x"] = x;
  start["data.y"] = y;
  Checkpoint.save(start, "builds/x2c-init.pt");

  Optimizer adam = Optimizer.adam(model, LR);
  for (int step = 0; step < STEPS; step++) {
    Scope.retain();
    defer Scope.release();
    adam.zero_grad();
    Tensor error = Tensor.mse_loss(_forward(model, x), y);
    error.backward();
    adam.step();
  }
  model.save("builds/x2c-model.pt");
  printf("loss %.8f\n", _loss(model, x, y));
  return 0;
}

static int _load(void) {
  Map start = Checkpoint.load("builds/x2c-init.pt");
  Tensor x = start["data.x"].tensor(), y = start["data.y"].tensor();
  Module model = _mlp();
  model.load("builds/python-model.pt");
  printf("loss %.8f\n", _loss(model, x, y));
  return 0;
}

int main(int argc, char **argv) {
  Scope.retain();
  defer Scope.release();
  if (argc > 1 && !strcmp(argv[1], "load")) return _load();
  return _train();
}
