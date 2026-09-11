# Training and Inference with torch

The `torch` package reaches PyTorch's C++ library, libtorch, from x2c.
Tensors, autograd, layers, optimizers, schedules, checkpoints,
TorchScript inference, and the MNIST reader are all libtorch's; the
package owns the language interface and the glue that makes them x2c
values. The entry unit is `packages/torch/src/torch.x`, the C ABI it
compiles over is `src/torch-2.10.h`, and `src/torch-shim.cpp` implements
that ABI. libtorch has no C API and no stable C++ ABI, so the shim is the
package's only C++ and it is tied to exactly the pinned version, 2.10.0.

A program links the pinned libtorch shared libraries dynamically through an
rpath into the prepared prefix, so it depends on that prefix at run time.
`torch.compile` and TorchScript capture work on
Python code and are not available here; x2c runs a TorchScript model but
cannot produce one.

```sh
make -C packages/torch prepare build test run
```

`prepare` downloads the pinned platform's libtorch archive into the shared
dependency cache; `run-mnist` and `verify-jit` are the commands for the
two examples that need the MNIST files and a Python-scripted model.

## Tensors

`Tensor.of` copies a List of numbers, or of nested Lists of rows, into a
tensor of a given shape and dtype. `zeros`, `ones`, `full`, `rand`,
`randn`, and `arange` build one without a value list, and `Tensor.scalar`
and `Tensor.scalar_integer` build a zero-dimensional one. The dtype
constants are `XT_UINT8`, `XT_INT8`, `XT_INT16`, `XT_INT32`, `XT_INT64`,
`XT_FLOAT16`, `XT_FLOAT32`, `XT_FLOAT64`, and `XT_BOOL`. `rank`, `size`,
`shape`, `numel`, and `dtype` report a tensor's structure, and
`Tensor.str` is libtorch's own printed form.

`Tensor.item` returns the one value of a single-element tensor as a `Var`
tagged by the tensor's dtype, `<long>` for an integer or bool tensor and
`<f64>` for a floating one, so `t.item().double()` and
`t.item().integer()` are the usual spellings. `Tensor.to_values` returns
every element in row-major order as an Array of the same Vars.

An integer dtype never passes through a double, so
`Tensor.of(%(9007199254740993), %(1), XT_INT64)` round-trips exactly and
so does doubling it. A shape or index List holds numbers; a bare name
inside `%()` is a Symbol, so `%(rows 2)` raises `<no-convert>` rather
than reading the Symbol's payload.

## Operators

`Tensor` adopts a protocol carrying `add`, `sub`, `mul`, `div`, `neg`,
and `matmul`, so `+ - * /` are elementwise, unary `-` negates, and `@` is
matrix multiplication, as in PyTorch. A `double` beside a `Tensor`
converts to a float64 scalar tensor and an `int` or `long` to an int64
one, which is why `2 * t` stays exact on an integer tensor. A `Tensor`
also boxes into a `Var`, and the operators work on the boxed form.

<!-- ignore: an import needs the built torch package archive. -->
```x2c,ignore
Tensor a = Tensor.of(%(1 2 3 4), %(2 2), XT_FLOAT64);
Tensor b = Tensor.of(%(1 0 0 1), %(2 2), XT_FLOAT64);
EXPECT_TRUE((a * b).equal(Tensor.of(%(1 0 0 4), %(2 2), XT_FLOAT64)));
EXPECT_TRUE((a @ b).equal(a));
EXPECT_NEAR((2.0 * a).sum().item().double(), 20.0, 1e-12);
```

## Indexing

`t[key]` reads three ways: an integer selects along the first dimension,
a List of integers selects each dimension in turn, so `t[%(1 2)]` is
`t.select(0, 1).select(0, 2)`, and a bool `Tensor` is a mask.
`select`, `narrow`, `slice`, `reshape`, `transpose`, `t`, `squeeze`,
`unsqueeze`, `flatten`, `index_select`, `masked_select`, `cat`, and
`stack` are the shape operations `torch.x` spells; results view the same
storage.

<!-- ignore: an import needs the built torch package archive. -->
```x2c,ignore
Tensor m = Tensor.of(%((1 2) (3 4)), %(2 2), XT_FLOAT64);
EXPECT_NEAR(m[%(1 0)].item().double(), 3.0, 1e-12);
Tensor mask = m.gt(Tensor.scalar(2.0, XT_FLOAT64));
EXPECT_INT_EQ(mask.dtype(), XT_BOOL);
EXPECT_NEAR(m[mask].sum().item().double(), 7.0, 1e-12);
```

## Lifetimes

Every record here, `Tensor`, `Module`, `Optimizer`, `Scheduler`, and
`JitModule`, owns one libtorch handle and is allocated with a `Scope`
finalizer, so a value is released with the scope that created it. A
training step is one `Scope.retain` and `Scope.release` pair around the
forward, backward, and update, with the model and optimizer in the
enclosing scope. `free` releases a handle early and returns NULL.

List results such as `parameters`, `named_parameters`, and generated tuples
intern their wrapper references in the current List pool. Scope release does
not reclaim those canonical cells. Long-running loops can bracket each
request with `List.pool_retain` and `List.pool_release`, releasing the request
Scope before its List pool. Keep stable parameter handles outside that
bracket when useful. Surviving values still need their ordinary Scope and
pool ownership; a pool bracket does not extend a Tensor wrapper's lifetime.

An unnamed operator temporary is released sooner. `Tensor` declares the
`discard` member of the [protocol chapter](protocols.md), so the compiler
releases the product in `a * b + c` right after the addition has used it,
and a long chain of operators keeps only its inputs and its result alive.
A value bound to a name is never discarded, so a loop variable reassigned
each step keeps its previous value until the scope ends; free it before the
assignment, or give each step its own scope, when such a chain is long.

## Autograd

`requires_grad_` marks a leaf that accumulates a gradient, `backward`
runs the backward pass, `grad` reads the accumulated gradient and raises
when none has been computed, and `zero_grad` clears it. `add_(b, alpha)`
is the in-place `a += alpha * b` of a hand-written update.
`Torch.no_grad` and `Torch.inference_mode` install a guard in the active
scope, so releasing that scope restores the previous mode, including the
release a `defer` runs while an Error transfers out. `inference_mode` is
the stronger of the two: its results carry no autograd metadata at all.
`Torch.grad_enabled` reports the current mode. From
`examples/fit-line.x`:

<!-- ignore: an import needs the built torch package archive. -->
```x2c,ignore
Tensor x = Tensor.arange(0.0, 8.0, 1.0, XT_FLOAT64).reshape(%(8 1));
Tensor y = 3.0 * x - 1.0;
Tensor w = Tensor.randn(%(1 1), XT_FLOAT64).requires_grad_(1);
for (int step = 0; step < 200; step++) {
  Scope.retain();
  defer Scope.release();
  Tensor error = Tensor.mse_loss(x @ w, y);
  error.backward();
  Torch.no_grad();
  w.add_(w.grad(), -0.02);
  w.zero_grad();
}
```

## Composing a model

A model is a `Module.composed()` root holding children registered under
names, and its forward is ordinary x2c. That forward never enters C++,
but libtorch still sees a module tree, so parameter enumeration,
`zero_grad`, the optimizers, and serialization all work and the names
match Python's `state_dict()`.

<!-- ignore: an import needs the built torch package archive. -->
```x2c,ignore
static Module _mlp(void) {
  Module model = Module.composed();
  model.register("l1", Module.linear(4, 8));
  model.register("l2", Module.linear(8, 1));
  return model;
}

static Tensor _forward(Module model, Tensor x) {
  Tensor hidden = model.child("l1").forward(x).tanh();
  return model.child("l2").forward(hidden);
}
```

A child's parameters are tensors, so
`x @ layer.parameters()[0].tensor().t() + layer.parameters()[1].tensor()`
is that affine step written out, as `examples/mlp.x` writes it.
`Module.forward` runs a native forward where libtorch has one; a composed
root has none and raises. `parameters`, `buffers`, `named_parameters`,
and `named_buffers` are recursive, and a child's names are qualified by
its registered name, so the model above enumerates
`l1.weight l1.bias l2.weight l2.bias`. `train`, `eval`, and `is_training`
carry the mode down the tree, so dropout and the normalizations read it;
`to_dtype` converts parameters and buffers together.

The native layers are `linear`, `conv1d`, `conv2d`, `batch_norm1d`,
`batch_norm2d`, `layer_norm`, `dropout`, `embedding`, `lstm`, `gru`,
`max_pool2d`, `avg_pool2d`, `flatten`, `relu`, `tanh`, `sigmoid`, and
`sequential`. Each takes PyTorch's arguments in PyTorch's order and its
defaults, and produces the names Python's `state_dict()` uses; beside
each one with more options is a `_with` form taking every one of them,
such as `conv2d_with(in, out, kernel, stride, padding, dilation, groups,
bias)`. `packages/torch/README.md` carries the full table.

`Module.sequential()` forwards its children in the order `Module.push`
appended them, naming each by its position, so `model.forward(images)` is
one call. The recurrent layers produce a state as well as a sequence and
run through `Module.forward_state`: `(output hidden)` for a GRU and
`(output hidden cell)` for an LSTM. `Tensor.mse_loss`, `.cross_entropy`
(int64 class targets), `.nll_loss`, and `.bce_with_logits` are the losses
`torch.x` spells; `.l1_loss` and `.huber_loss` come from the generated
tier with the schema's own reduction argument, where 1 is the mean.

## Training

`Optimizer.sgd`, `.sgd_momentum`, `.adam`, `.adamw`, `.rmsprop`, and
`.adagrad` build over a module's parameters, and `Optimizer.over` takes a
List of loose tensors with one of `XT_SGD .. XT_ADAGRAD`. `lr` and
`set_lr` read and write every parameter group. libtorch's `DataLoader` is
a template over a compile-time dataset and cannot cross a C ABI, so
mini-batching is x2c: a permutation and an `index_select`.

<!-- ignore: an import needs the built torch package archive. -->
```x2c,ignore
Optimizer adam = Optimizer.adam(model, 0.05);
for (int step = 0; step < 200; step++) {
  Scope.retain();
  defer Scope.release();
  Tensor pick = Torch.randperm(64).narrow(0, 0, 16);
  adam.zero_grad();
  Tensor error = Tensor.mse_loss(_forward(model, x.index_select(0, pick)),
                                 y.index_select(0, pick));
  error.backward();
  adam.step();
}
```

libtorch ships exactly two learning-rate schedules, `Scheduler.step_lr`
and `Scheduler.reduce_on_plateau`; the first advances with `step`, the
second with `step_metric`. The other three are x2c arithmetic over
`Optimizer.lr` and `set_lr`, each writing the rate for the number of
completed `step` calls, starting at construction with none taken:

- `Scheduler.cosine(o, t_max, eta_min)` anneals along a half cosine:
  after `t` steps the rate is
  `eta_min + (lr - eta_min) * (1 + cos(pi * t / t_max)) / 2`, and it
  stays at `eta_min` past `t_max`.
- `Scheduler.linear_warmup(o, steps, base_lr)` raises the rate from
  `base_lr / steps` to `base_lr`: `base_lr * min(1, (t + 1) / steps)`.
- `Scheduler.multistep(o, milestones, gamma)` multiplies the rate by
  `gamma` once for each milestone step count reached, as PyTorch's
  `MultiStepLR` does.

`Scheduler.steps` reports how many steps an x2c schedule has taken, and
`step_metric` on one raises: it advances without a metric.

## Checkpoints and Python

`Module.save` writes a pickled dict of name to tensor and `Module.load`
reads one, requiring every parameter and buffer name to be present.
`Checkpoint.save` and `Checkpoint.load` are the same format over a Map.
Two rules govern the Python side:

- Python must save a plain dict:
  `torch.save(dict(model.state_dict()), path)`. The `OrderedDict` that
  `state_dict()` returns does not unpickle in C++.
- Python must read with `weights_only=False`, or allow the tag the C++
  pickler writes:
  `torch.serialization.add_safe_globals([torch.jit._pickle.restore_type_tag])`.

`Module.save_archive` and `load_archive` use libtorch's own archive
instead; Python reads that only through `torch.jit.load`. Optimizer state
saves and loads through the C++ archive for resuming in x2c or C++.
Adam additionally supports explicit Python state-dict exchange through
`Optimizer.save_python` and `load_python`, described below.

## TorchScript inference

`JitModule.load` reads a module Python scripted or traced, `forward`
takes a List of Tensor and returns a List of Tensor, one entry for a
tensor result and one per element for a tuple of tensors, and `train` and
`eval` set the mode. A file that is not TorchScript raises `<bad-state>`.
From `examples/jit-infer.x`:

<!-- ignore: an import needs the built torch package archive. -->
```x2c,ignore
JitModule model = JitModule.load(path);
model.eval();
Torch.inference_mode();
List results = model.forward(%($x));
Tensor logits = results[0].tensor();
```

`make -C packages/torch verify-jit` scripts a 2-layer MLP in the pinned
Python torch, runs the example over a fixed batch, and compares every
number with Python's: `verify-jit: agreed on 8 values`.

## MNIST

`Torch.mnist(root, train)` reads the four IDX files under `root` through
libtorch's own reader and returns `(images targets)`: an N x 1 x 28 x 28
float32 tensor scaled to [0, 1] and N int64 classes. The reader checks
the published row counts, 60,000 and 10,000. `examples/mnist.x` trains a
sequential convolutional model for one epoch with Adam and a cosine
anneal, then reports accuracy on the test set. It takes the data
directory as an argument or from `TORCH_MNIST`, and prints where to
obtain the files when they are absent:

```sh
make -C packages/torch run-mnist TORCH_MNIST=/path/to/mnist
```

```text
mnist /tmp/mnist-real  train 60000  test 10000
batch    0  loss 2.335118  lr 0.001000
batch  900  loss 0.337217  lr 0.000103
test accuracy 0.9323
```

That run used the published files, in 3.8 seconds on that machine. The
tests build a 10,000-row synthetic IDX set instead, so `make test`
exercises the reader without the download.

## The generated operator tier

`src/torch-ops.x` is generated by `tools/gen-ops.py` from the pinned
operator schema in `schema/`, beside `src/torch.x`. It binds 1182
operators as `Tensor` methods with the schema's own argument structure:
`int` is `long`, `float` is `double`, a `Scalar` is a `Var` that keeps
integer and floating values distinct, an absent optional is `Var.null()`
or a NULL `Tensor`, `int[]` is a `List`, `Tensor[]` is a `List` of
tensors, and tuple results come back as a `List`. Where the two units
share a name, `torch.x` wins and the generated overload takes a suffix,
so `sum.dim_IntList` is `Tensor.sum_dim`.

`packages/torch/schema/README.md` records the pinned schema file and its
checksum, then a table of counts measured by `make gen-ops`: 2666 entries
parsed, 1193 selected, and each rejection reason with its count. Below
the table it names what this tier leaves out, including every `out=`
form, named tensors, `Dimname` overloads, the `_foreach_*` family, custom
autograd functions, and everything the private `_`-prefixed operators
reach.

## Errors

A failure inside libtorch raises `<bad-state>` with `(library "torch")`,
the operation name, and the first line of libtorch's message; the full
message stays available through `xt_last_error_full` in the raw API.
Every entry point in `torch-2.10.h` catches, so no C++ exception crosses
the ABI. This arm in `examples/mlp.x` prints `caught matmul: mat1 and
mat2 shapes cannot be multiplied (3x5 and 4x8)`.

<!-- ignore: an import needs the built torch package archive. -->
```x2c,ignore
try { (void) _forward(model, Tensor.randn(%(3 5), XT_FLOAT32)); }
catch %(bad-state (library "torch") *detail): {
  String operation = detail.assoc(<operation>).string();
  String reason = detail.assoc(<reason>).string();
  printf("%s", %"caught $operation: $reason\n");
}
```

## Devices, optimizer exchange, custom gradients, and Lisp

The macOS arm64 profile supports CPU and MPS. The Linux x86_64 profile
uses the pinned CPU archive and the system C++ runtime. GPU support on Linux
and CUDA are outside these profiles. Device names are ordinary strings;
`Tensor.to_device(device, dtype, non_blocking, copy)` already belongs to the
generated operator surface. `Module.to_device(device)` moves parameters and
buffers; call it before constructing an optimizer. Existing constructors keep
their CPU behavior. MPS tensors use float32 or a supported integer dtype;
MPS cannot represent float64. `to_values` explicitly copies to CPU before
reading values. `Torch.mps_available()` reports availability, and
`Torch.mps_synchronize()` waits for queued kernels when measuring execution.

```sh
TORCH_MNIST=/path/to/mnist TORCH_EPOCHS=2 TORCH_DEVICE=mps \
  make -C packages/torch run-mnist
```

The MNIST example defaults to one epoch. It writes a model checkpoint and
compares held-out accuracy after reload. On the development MPS device,
two epochs reached 95.23% and the reloaded model reached the same accuracy.
Generated operators still depend on MPS kernel coverage. With fallback disabled,
`make -C packages/torch verify-mps` records that `Tensor.linalg_eig` raises the
native error because `aten::linalg_eig` is unavailable on MPS in 2.10.0.
This is a focused limitation probe, not a claim that all generated operators
run on MPS.

`Optimizer.save_python(path)` and `load_python(path)` exchange Adam's
`state_dict()` layout, including parameter groups, moments, exact step counts,
and AMSGrad state. Parameter IDs match the destination's parameters by order;
use the same parameter order when constructing both optimizers. Import parses
all groups and states before replacing the optimizer. Numeric options import
by value, including integers and scalar tensors. Unsupported semantic options
such as `maximize`, `capturable`, `differentiable`, and decoupled
weight decay are rejected. Backend execution flags become the ordinary scalar
implementation. Existing `save`/`load` retain their C++ archive format.
Other optimizer algorithms still use that archive format.

Python reads the file with `torch.load(path, weights_only=False)` and passes
its dictionary to `optimizer.load_state_dict`. Python model checkpoints must
use `dict(model.state_dict())`, as described in the checkpoint section.
`make -C packages/torch verify-interchange` checks every parameter, moment
and option through both
resume directions, multiple groups and an uninitialized optimizer. Its
`LibtorchAdam` reference uses libtorch's operation order. Stock Python Adam
remains a separately measured comparison; the package does not promise
bit-identical long training against its different floating-point order.

`Tensor.custom(forward, backward, inputs)` creates one differentiable output.
The forward Func receives an `AutogradContext` and a List of inputs; backward
receives that context and the output gradient, and returns one Tensor or Null
per input. `save_for_backward`, `saved_tensors`, and `needs_input_grad` expose
native autograd's saved values and input-gradient requirements. Saved native
tensors outlive callback wrappers. Funcs and their captured referents remain
borrowed and must outlive the graph on its creating thread.

Use `output.backward_callbacks()` for custom graphs. It temporarily disables
autograd's worker scheduling, executes CPU or MPS callbacks on the invoking
thread and restores the prior scheduling state. It does not change native
kernel thread counts. Callback Errors are caught before returning to C++ and
re-raised after the native call returns. Initial custom functions have one
output and first-order gradients; in-place input changes, nested custom
callbacks, reentrant backward and higher-order differentiation are unsupported.
Callback contexts cannot escape. Custom graphs are not serializable.
Custom forward also runs under `Torch.inference_mode`. Inputs must still not
be mutated; inference tensors have no version counters to diagnose mutation.

`packages/torch/examples/custom-activation.x` trains a network through an
x2c swish derivative:

```sh
make -C packages/torch run-custom
TORCH_DEVICE=mps make -C packages/torch run-custom
make -C packages/torch verify-custom
```

`TorchLisp.install(lisp)` installs tensor construction, arithmetic, readers,
linear models, optimizers, training, model checkpoints and `torch-free`.
`torch-values` returns an ordinary Lisp List; `torch-item` preserves integer
values. Native values created during evaluation belong to the existing Lisp
session. Caller-injected values retain their existing ownership.
`packages/torch/examples/inline-lisp.x` builds and trains a persistent model
through these
ordinary operations, with no native training-loop binding.

```sh
make -C packages/torch run-lisp
make -C packages/torch verify-lifetimes
```

`torch-free` releases native resources early and invalidates every alias of
that object. Wrappers remain in the session Scope until `Lisp.destroy`;
repeated evaluation therefore has measurable wrapper growth even when native
handle counts stay flat. Release prediction and loss tensors after each
training step. Bare no-grad or inference guards are not Lisp bindings because
their lifetime would otherwise extend to session destruction. The optional
lifetime check builds isolated instrumented objects using the existing handle
hooks. In 128 measured Lisp steps, native handles stayed at four while Scope
allocations grew from 355 to 2159. Session destruction returned native handles
to baseline; 64 custom graphs also returned to baseline after each graph.

## Limits

- macOS arm64 CPU/MPS and Linux x86_64 CPU; no CUDA profile.
- No distributed training.
- Python optimizer interchange covers Adam; other optimizers retain the
  C++ archive format. Module state works in both directions.
- The generated operator tier is a function count, not coverage:
  `packages/torch/schema/README.md` names the families it leaves out. The
  design is in `plans/archive/x2c-torch.md`.
- Custom autograd currently supports one output and first-order gradients.
- `torch.compile` and TorchScript capture of x2c code are not possible:
  they capture Python. x2c runs a TorchScript model but cannot produce
  one. Agreement with Python is to float32 tolerance, not bit exact.
