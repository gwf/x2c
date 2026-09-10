/*  mlp.x -- Train a 4-8-1 network on synthetic data, then reload it.

    The model is a composed Module holding two Linear children. Its
    forward is ordinary x2c: `@` for the matrix product and `+` for the
    bias, over the parameters libtorch owns.
*/

import "torch" with Torch, Tensor, Module, Optimizer;

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

int main(void) {
  Scope.retain();
  defer Scope.release();
  Torch.manual_seed(0);

  /* y is a fixed linear combination of the inputs plus a small offset and
     a little noise, so the network has something learnable to find. */
  Tensor x = Tensor.randn(%(64 4), XT_FLOAT32);
  Tensor weights = Tensor.of(%(0.5 -1.25 2.0 0.75), %(1 4), XT_FLOAT32);
  Tensor y = x @ weights.t() + 0.5 + Tensor.randn(%(64 1), XT_FLOAT32) * 0.05;

  Module model = _mlp();
  Optimizer adam = Optimizer.adam(model, 0.05);
  for (int step = 0; step < 200; step++) {
    Scope.retain();
    {
      defer Scope.release();
      /* A mini-batch is a permutation and an index_select, written here
         rather than borrowed from a C++ DataLoader. */
      Tensor pick = Torch.randperm(64).narrow(0, 0, 16);
      adam.zero_grad();
      Tensor error = Tensor.mse_loss(_forward(model, x.index_select(0, pick)),
                                     y.index_select(0, pick));
      error.backward();
      adam.step();
    }
    if (step % 50 == 0)
      printf("step %3d  loss %.6f\n", step, _loss(model, x, y));
  }
  printf("trained  loss %.6f\n", _loss(model, x, y));

  model.save("builds/mlp.pt");
  Module reloaded = _mlp();
  reloaded.load("builds/mlp.pt");
  printf("reloaded loss %.6f\n", _loss(reloaded, x, y));

  try {
    (void) _forward(model, Tensor.randn(%(3 5), XT_FLOAT32));
  }
  catch %(bad-state (library "torch") *detail): {
    String operation = detail.assoc(<operation>).string();
    String reason = detail.assoc(<reason>).string();
    printf("%s", %"caught $operation: $reason\n");
  }
  return 0;
}
