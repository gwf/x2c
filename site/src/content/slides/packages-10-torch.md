---
section: packages
tab: torch
title: Compose a model. Train it. Save it.
---

<!-- ignore: adapted excerpt; the complete example requires its optional package and setup. -->
```x2c,ignore
import "torch" with Torch, Tensor, Module, Optimizer;

Module model = Module.composed();
model.register("l1", Module.linear(4, 8));
model.register("l2", Module.linear(8, 1));

static Tensor forward(Module m, Tensor x) =>
  m.child("l2").forward(
    m.child("l1").forward(x).tanh()
  );

Optimizer adam = Optimizer.adam(model, 0.05);
for (int step = 0; step < 200; step++) {
  Scope.retain();
  defer Scope.release();
  adam.zero_grad();
  Tensor.mse_loss(forward(model, x), y).backward();
  adam.step();
}

model.save("mlp.pt");
// torch.load reads it in Python.
```

Register two linear layers, write the forward pass in x2c, and train
with Adam. `backward` computes gradients through both layers; each step
releases its temporary tensors. The saved model contains named weights
and biases that Python can read with
`torch.load("mlp.pt", weights_only=False)`.

This excerpt assumes training tensors `x` and `y`. The complete example
adds synthetic data, mini-batches, and a save/reload check. Its training
and reload output:

```text
step   0  loss 5.294546
step  50  loss 0.239890
step 100  loss 0.081145
step 150  loss 0.035499
trained  loss 0.024875
reloaded loss 0.024875
```

The package uses PyTorch's libtorch on macOS arm64, with CPU tensors.
Programs need the prepared libtorch libraries at runtime.

[Full example](https://github.com/gwf/x2c/blob/main/packages/torch/examples/mlp.x) / [Package guide](https://github.com/gwf/x2c/blob/main/packages/torch/README.md)
