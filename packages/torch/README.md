# torch

Experimental. Tensors, autograd, modules, optimizers, schedulers, and
checkpoints over the pinned libtorch 2.10.0, PyTorch's C++ library. The
entry unit is `src/torch.x`; the C ABI it compiles over is
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
`double` beside a `Tensor` converts to a float64 scalar tensor and an `int`
or `long` to an int64 one, so `2 * t` stays exact on an integer tensor.

```sh
make -C packages/torch prepare build test run
```

`prepare` downloads the official 77 MB libtorch archive into the shared
dependency cache; nothing is built. `run` builds and runs both examples.

## Values and dtypes

`Tensor.item` returns a `Var` tagged by the tensor's dtype, `<long>` for an
integer or bool tensor and `<f64>` for a floating one, and `Tensor.to_values`
returns an Array of the same. Write `t.item().double()` where a double is
wanted. An integer dtype never passes through a double, so
`Tensor.of(%(9007199254740993), %(1), XT_INT64)` round-trips exactly.

`t[key]` reads three ways: an integer selects along the first dimension, a
bool `Tensor` is a mask and selects the matching elements, and a List of
integers selects each dimension in turn, so `t[%(1 2)]` is
`t.select(0, 1).select(0, 2)`.

## Composing a model

A model is a `Module.composed()` root holding registered children. Its
forward is ordinary x2c: nothing about it enters C++, but libtorch still
sees a module tree, so parameter enumeration, `zero_grad`, the optimizers,
and serialization all work and the names match Python's `state_dict()`.

```x2c
Module model = Module.composed();
model.register("l1", Module.linear(4, 8));
model.register("l2", Module.linear(8, 1));

static Tensor _affine(Module layer, Tensor x) {
  List parameters = layer.parameters();
  return x @ parameters[0].tensor().t() + parameters[1].tensor();
}

static Tensor _forward(Module model, Tensor x) =>
  _affine(model.child("l2"), _affine(model.child("l1"), x).tanh());
```

`Module.forward` runs a native forward where libtorch has one, such as a
`Linear`'s; a composed root has none and raises. `parameters`, `buffers`,
`named_parameters`, and `named_buffers` are recursive; `train`/`eval` and
`is_training` carry the mode down the tree.

`Optimizer.sgd`, `.sgd_momentum`, `.adam`, `.adamw`, `.rmsprop`, and
`.adagrad` build over a module's parameters, and `Optimizer.over` takes a
List of loose tensors with one of `XT_SGD .. XT_ADAGRAD`. `lr` and `set_lr`
read and write every parameter group. `Scheduler.step_lr` and
`Scheduler.reduce_on_plateau` are the two schedules libtorch ships; the
first advances with `step`, the second with `step_metric`.

## Examples

`examples/fit-line.x` fits `y = 3x - 1` by hand-written gradient descent:

```text
step   0  loss 152.263024
step  50  loss 0.233426
step 100  loss 0.073190
step 150  loss 0.022949
w 2.969  b -0.845  loss 7.36e-03
```

`examples/mlp.x` trains the 4-8-1 network above with Adam on 64 synthetic
rows, in mini-batches of 16 built from `Torch.randperm` and `index_select`,
then saves the model and reloads it into a fresh one:

```text
step   0  loss 5.294546
step  50  loss 0.239890
step 100  loss 0.081145
step 150  loss 0.035499
trained  loss 0.024875
reloaded loss 0.024875
caught matmul: mat1 and mat2 shapes cannot be multiplied (3x5 and 4x8)
```

## Checkpoints

`Module.save` writes a pickled dict of name to tensor and `Module.load`
reads one, requiring every parameter and buffer name to be present.
`Checkpoint.save` and `Checkpoint.load` are the same format over a Map, for
saving data or optimizer-adjacent tensors beside a model. Two rules govern
the Python side:

- Python must save a plain dict: `torch.save(dict(model.state_dict()), path)`.
  The `OrderedDict` that `state_dict()` returns does not unpickle in C++.
- Python must read with `weights_only=False`, or allow the tag the C++
  pickler writes:
  `torch.serialization.add_safe_globals([torch.jit._pickle.restore_type_tag])`.

`Module.save_archive`/`load_archive` use libtorch's own archive instead;
Python reads that only through `torch.jit.load`.

`make -C packages/torch verify-python` checks agreement in both directions
against a CPython with the pinned wheel (`TORCH_PYTHON`, defaulting to
`/Users/gary/Git/Bonsai-demo/.venv/bin/python`). It is not part of `test`.
x2c trains 20 Adam steps from seed 0, Python replays them from the saved
initial parameters and data, then Python's trained weights are evaluated on
both sides:

```text
torch 2.10.0 at /Users/gary/Git/Bonsai-demo/.venv/bin/python
trained loss                 x2c 0.59051228  python 0.59051239  relative 1.95e-07
python weights in x2c        x2c 0.59051239  python 0.59051239  relative 8.31e-09
verify-python: agreed
```

## Generated operators

`src/torch-ops.x` is generated by `tools/gen-ops.py` from the pinned
operator schema in `schema/`, beside the hand-written `src/torch.x`. It
binds 1182 operators as `Tensor` methods with the schema's own argument
structure: `int` is `long`, `float` is `double`, a `Scalar` is a `Var` that
keeps integer and floating values distinct, an absent optional is
`Var.null()` or a NULL `Tensor`, `int[]` is a `List`, `Tensor[]` is a
`List` of tensors, and tuple results come back as a `List`. The hand-written
unit keeps the operator protocol rows, creation from Lists, autograd, and
the exact `item`; where the two units share a name, `torch.x` wins and the
generated overload takes a suffix. `schema/README.md` records how the
schema was selected and what tier 1 leaves out. `make verify-ops` compares
a sample against the pinned Python torch:

```text
23 operators compared, 0 disagreed, largest delta 0
```

## Lifetimes

Every record here, `Tensor`, `Module`, `Optimizer`, and `Scheduler`, is
allocated with a `Scope` finalizer, so an operator temporary is released
with the scope that created it. A training step is one `Scope.retain` and
`Scope.release` pair around the forward, backward, and update; the model
and optimizer live in the enclosing scope. `free` releases a handle early
and returns NULL.

`Torch.no_grad` and `Torch.inference_mode` are scoped the same way: each
installs a guard in the active scope, and releasing that scope restores the
previous mode, including the release a `defer` runs while an Error transfers
out.

```x2c
Scope.retain();
{
  defer Scope.release();
  Torch.no_grad();
  parameter.add_(parameter.grad(), -rate);
}
```

## Errors

A failure inside libtorch raises `<bad-state>` with `(library "torch")`, the
operation name, and the first line of libtorch's message; the full message
stays available through `xt_last_error_full` in the raw API. Every entry
point in `torch-2.10.h` catches, so no C++ exception crosses the ABI: a
function returning a handle returns NULL on failure, and one producing a
scalar returns a status and writes its result through an out parameter.

## Not self-contained

Programs link `libtorch_cpu.dylib` (213 MB) dynamically by an rpath into
the prepared prefix. Static libtorch is not practical, so a torch program
depends on that prefix at run time, unlike every other x2c artifact.

## Limits

- macOS arm64, CPU only.
- Optimizer state saves and loads through the C++ archive only; that file
  is for resuming in x2c or C++, not for Python. Module state is
  interoperable in both directions.
- Native modules so far are `Linear`; convolution, normalization, dropout,
  embeddings, and recurrent layers arrive with M3. The generated operator
  tier is a function count, not coverage: `schema/README.md` names the
  families it leaves out. The design is in `plans/x2c-torch.md`.
- No `autograd.Function`: a custom node cannot be written in x2c yet.
- `torch.compile` and TorchScript capture of x2c code are not possible:
  they capture Python. x2c can load a TorchScript model in a later
  milestone but cannot produce one. Agreement with Python is to float32
  tolerance, not bit exact.
