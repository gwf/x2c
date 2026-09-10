# torch

Experimental. Tensors, autograd, and, in later milestones, modules,
optimizers, and checkpoints over the pinned libtorch 2.10.0, PyTorch's C++
library. The entry unit is `src/torch.x`; the C ABI it compiles over is
`src/torch-2.10.h`, implemented by `src/torch-shim.cpp`. libtorch has no C
API and no stable C++ ABI, so the shim is this package's only C++ and it is
tied to exactly the pinned version.

```x2c
import "torch" with Torch, Tensor;

Tensor x = Tensor.arange(0.0, 8.0, 1.0, XT_FLOAT64).reshape(%(8 1));
Tensor y = 3.0 * x - 1.0;
Tensor w = Tensor.randn(%(1 1), XT_FLOAT64).requires_grad_(1);
Tensor error = Tensor.mse_loss(x @ w, y);
error.backward();
```

`*` is elementwise and `@` is matrix multiplication, as in PyTorch. A
`double` beside a `Tensor` converts to a float64 scalar tensor.

```sh
make -C packages/torch prepare build test run
```

`prepare` downloads the official 77 MB libtorch archive into the shared
dependency cache; nothing is built. `run` builds and runs `examples/fit-line.x`,
which fits `y = 3x - 1` by gradient descent:

```text
step   0  loss 152.263024
step  50  loss 0.233426
step 100  loss 0.073190
step 150  loss 0.022949
w 2.969  b -0.845  loss 7.36e-03
```

## Lifetimes

A `Tensor` record is allocated with a `Scope` finalizer, so every tensor,
including an operator temporary, is released with the scope that created
it. A training step is one `Scope.retain` and `Scope.release` pair around
the forward, backward, and update; the leaf parameters live in the
enclosing scope. `free` releases a handle early and returns NULL.

## Errors

A failure inside libtorch raises `<bad-state>` with `(library "torch")`,
the operation name, and the first line of libtorch's message; the full
message stays available through `xt_last_error_full` in the raw API.

## Not self-contained

Programs link `libtorch_cpu.dylib` (213 MB) dynamically by an rpath into
the prepared prefix. Static libtorch is not practical, so a torch program
depends on that prefix at run time, unlike every other x2c artifact.

## Limits

- macOS arm64, CPU only, in this milestone.
- Modules, optimizers, and checkpoints arrive in the next milestone; the
  design and evidence are in `plans/x2c-torch.md`.
- `torch.compile` and TorchScript capture of x2c code are not possible: they
  capture Python. Agreement with Python is to float32 tolerance, not bit
  exact.
