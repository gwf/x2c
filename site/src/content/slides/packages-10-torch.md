---
slug: torch
section: packages
tab: torch
title: Compose a model. Train it. Save it.
links:
  - label: Full source
    href: https://github.com/gwf/x2c/blob/main/packages/torch/examples/mlp.x
  - label: Package guide
    href: https://github.com/gwf/x2c/blob/main/packages/torch/README.md
  - label: Performance comparison
    href: docs/guide/torch.html#performance
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
with Adam. Each step releases its temporary tensors. Save the named
weights and biases for Python to read with `torch.load`.

The complete example supplies training data and checks that reloading
preserves the result:

```text
trained  loss 0.024875
reloaded loss 0.024875
```

Uses PyTorch's libtorch: CPU or MPS on macOS arm64, CPU on Linux x86_64.
The prepared libraries are required at runtime.
