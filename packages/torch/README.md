# torch

The book's [Training and Inference with torch](../../docs/src/guide/torch.md)
chapter explains the package through advanced workflows.

Tensors, autograd, layers, optimizers, schedules,
checkpoints, TorchScript inference, and MNIST over the pinned libtorch
2.10.0, PyTorch's C++ library. The
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

`prepare` downloads the pinned platform's libtorch archive into the shared
dependency cache; nothing is built. `run` builds and runs the two examples
that need nothing else; `run-mnist` and `verify-jit` are the commands for
the two that need the MNIST files and a Python-scripted model.

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

`Module.forward` runs a native forward where libtorch has one; a composed
root has none and raises. `parameters`, `buffers`, `named_parameters`, and
`named_buffers` are recursive; `train`/`eval` and `is_training` carry the
mode down the tree, so dropout and the normalizations read it. `to_dtype`
converts parameters and buffers together.

## Native layers

Each constructor takes PyTorch's arguments in PyTorch's order and produces
the parameter and buffer names Python's `state_dict()` uses;
`make verify-python` compares them against the pinned wheel.

| x2c | PyTorch |
| --- | --- |
| `Module.linear(in, out)` | `nn.Linear` |
| `Module.conv1d(in, out, kernel)` | `nn.Conv1d` |
| `Module.conv2d(in, out, kernel)` | `nn.Conv2d` |
| `Module.batch_norm1d(features)` | `nn.BatchNorm1d` |
| `Module.batch_norm2d(features)` | `nn.BatchNorm2d` |
| `Module.layer_norm(shape)` | `nn.LayerNorm` |
| `Module.dropout(p)` | `nn.Dropout` |
| `Module.embedding(rows, dim)` | `nn.Embedding` |
| `Module.lstm(in, hidden, layers, batch_first)` | `nn.LSTM` |
| `Module.gru(in, hidden, layers, batch_first)` | `nn.GRU` |
| `Module.max_pool2d(kernel)` | `nn.MaxPool2d` |
| `Module.avg_pool2d(kernel)` | `nn.AvgPool2d` |
| `Module.flatten()` | `nn.Flatten` |
| `Module.relu()`, `.tanh()`, `.sigmoid()` | `nn.ReLU` and friends |
| `Module.sequential()` | `nn.Sequential` |

A plain constructor takes PyTorch's defaults, as `Module.linear` does for
its bias. Beside each one that has more options is a `_with` form taking
every one of them in PyTorch's order: `linear_bias(in, out, bias)`,
`conv1d_with` and
`conv2d_with(in, out, kernel, stride, padding, dilation, groups, bias)`,
`batch_norm1d_with` and
`batch_norm2d_with(features, eps, momentum, affine, track_running_stats)`,
`layer_norm_with(shape, eps, affine)`,
`max_pool2d_with` and `avg_pool2d_with(kernel, stride, padding)`, and
`flatten_with(start_dim, end_dim)`. `Module.register_parameter` and
`Module.register_buffer` add a tensor under a name to any module, and
`Optimizer.adam_with` exposes Adam's betas, epsilon, weight decay, and
amsgrad. `Module.push`
names each child by its position, "0", "1", and so on, so a sequential
model's state names match Python's, and `Module.forward` runs the children
in order:

```x2c
Module model = Module.sequential();
model.push(Module.conv2d(1, 8, 3));
model.push(Module.relu());
model.push(Module.max_pool2d(2));
model.push(Module.flatten());
model.push(Module.linear(8 * 13 * 13, 10));
Tensor logits = model.forward(images);
```

The recurrent layers produce a state as well as a sequence, so they run
through `Module.forward_state`, which returns `(output hidden)` for a GRU
and `(output hidden cell)` for an LSTM.

`Tensor.mse_loss`, `.cross_entropy` (int64 class targets), `.nll_loss`, and
`.bce_with_logits` are the losses the hand-written unit spells; `.l1_loss`
and `.huber_loss` come from the generated tier with the schema's own
reduction argument, where 1 is the mean.

## Optimizers and schedules

`Optimizer.sgd`, `.sgd_momentum`, `.adam`, `.adamw`, `.rmsprop`, and
`.adagrad` build over a module's parameters, and `Optimizer.over` takes a
List of loose tensors with one of `XT_SGD .. XT_ADAGRAD`. `lr` and `set_lr`
read and write every parameter group.

libtorch ships exactly two learning-rate schedules, `Scheduler.step_lr` and
`Scheduler.reduce_on_plateau`; the first advances with `step`, the second
with `step_metric`. The other three are x2c arithmetic over
`Optimizer.lr`/`set_lr`, each writing the rate for the number of completed
`step` calls, starting at construction with none taken:

- `Scheduler.cosine(o, t_max, eta_min)` anneals along a half cosine:
  after `t` steps the rate is
  `eta_min + (lr - eta_min) * (1 + cos(pi * t / t_max)) / 2`, and it stays
  at `eta_min` past `t_max`.
- `Scheduler.linear_warmup(o, steps, base_lr)` raises the rate from
  `base_lr / steps` to `base_lr`: `base_lr * min(1, (t + 1) / steps)`.
- `Scheduler.multistep(o, milestones, gamma)` multiplies the rate by
  `gamma` once for each milestone step count reached, as PyTorch's
  `MultiStepLR` does.

`Scheduler.steps` reports how many steps an x2c schedule has taken, and
`step_metric` on one raises: it advances without a metric.

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

## TorchScript inference

x2c loads and runs a module Python scripted or traced; it cannot produce
one. `JitModule.load` reads the file, `forward` takes a List of Tensor and
returns a List of Tensor, one entry for a tensor result and one per element
for a tuple of tensors, and `train`/`eval` set the mode. A file that is not
TorchScript raises `<bad-state>`.

`make -C packages/torch verify-jit` scripts a 2-layer MLP with fixed
weights in the pinned Python torch, runs `examples/jit-infer.x` over a
fixed batch, and compares every number with Python's:

```text
torch 2.10.0 at /Users/gary/Git/Bonsai-demo/.venv/bin/python
model builds/scripted.pt
input ( 2 4 )
logits 0 -0.230555 0.082929 0.396414
logits 1 -0.471286 0.402971 1.277228
tuple results 2
classes 2.000000 2.000000
verify-jit: agreed on 8 values
```

## MNIST

`Torch.mnist(root, train)` reads the four IDX files under `root` through
libtorch's own reader and returns `(images targets)`: an N x 1 x 28 x 28
float32 tensor scaled to [0, 1] and N int64 classes. The reader checks the
published row counts, 60,000 and 10,000. Batching is x2c, a `randperm` and
an `index_select`, because libtorch's `DataLoader` is a template over a
compile-time dataset and cannot cross a C ABI.

`examples/mnist.x` trains the sequential CNN above for one epoch with Adam
and a cosine anneal, then reports accuracy on the test set. It takes the
data directory as an argument or from `TORCH_MNIST`, and prints where to
obtain the files when they are absent:

```sh
make -C packages/torch run-mnist TORCH_MNIST=/path/to/mnist
```

```text
mnist /tmp/mnist-real  train 60000  test 10000
batch    0  loss 2.335118  lr 0.001000
batch  100  loss 0.508674  lr 0.000974
batch  200  loss 0.374458  lr 0.000902
batch  300  loss 0.326470  lr 0.000790
batch  400  loss 0.422208  lr 0.000651
batch  500  loss 0.274723  lr 0.000501
batch  600  loss 0.151049  lr 0.000357
batch  700  loss 0.305595  lr 0.000234
batch  800  loss 0.399686  lr 0.000146
batch  900  loss 0.337217  lr 0.000103
test accuracy 0.9323
```

That run used the published MNIST files, one epoch in 3.8 seconds on this
machine. The tests build their own 10,000-row synthetic IDX set instead, so
`make test` exercises the reader without the download.

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
module state names          10 modules, 31 names identical
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
allocated with a `Scope` finalizer, so a value is released with the scope
that created it. A training step is one `Scope.retain` and `Scope.release`
pair around the forward, backward, and update; the model and optimizer
live in the enclosing scope. `free` releases a handle early and returns
NULL.

List results such as `parameters`, `named_parameters`, and generated tuples
intern their wrapper references in the current List pool. Releasing a Scope
does not reclaim those canonical cells. Long-running loops that create these
Lists can bracket each request with `List.pool_retain` and
`List.pool_release`, releasing the request Scope before its List pool.
Keep stable parameter handles outside that bracket when useful. Surviving
values still need their ordinary Scope and pool ownership; a pool bracket
does not extend a Tensor wrapper's lifetime. The canonical-churn measurements
in [the comparison report](benchmarks/REPORT.md) separate these costs.

An unnamed operator temporary does not wait for the scope. `Tensor`
declares the `discard` protocol member, so the compiler releases the
product in `a * b + c`, or the converted `2.0` in `2.0 * x`, right after
the operator that consumes it returns. A chain of operators keeps only its
inputs and its result alive; a value bound to a name is never discarded.
A loop variable reassigned each step therefore keeps its previous value
until the scope ends: `y = (y * a + b).relu()` retains one tensor per
step. Free it before the assignment when the chain is long, or give each
step its own scope. `benchmarks/REPORT.md` measures both.

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
Argument checks the package makes itself raise `<bad-arg>` instead:
`Tensor.item` on a tensor with more than one element, and a `Tensor.of`
whose values do not fill its shape. The raw handle of any record is its
`native()` accessor; `Tensor.adopt` and `Torch.check` bring a raw call's
handle or status back under these rules.

## Threads

libtorch brings its own intra-op and inter-op thread pools into the
process. `Torch.set_num_threads` pins the intra-op pool and
`Torch.set_num_interop_threads` the inter-op pool; the latter is accepted
only before that pool starts. `Torch.num_threads` and
`Torch.num_interop_threads` read the current sizes.

## Benchmarks

`benchmarks/` holds the matched x2c and PyTorch applications from
`plans/archive/x2c-torch-comparison.md`: tabular regression, the MNIST CNN,
sequence forecasting, and an interop diagnostic, with a runner for
correctness, timing, and memory modes. They are outside every package
target and gate; `benchmarks/README.md` gives the commands and
`benchmarks/PILOT.md` the measured pilot.

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
use `dict(model.state_dict())`, as described above. The optional
`make -C packages/torch verify-interchange` checks every parameter, moment
and option through both resume directions, multiple groups and an
uninitialized optimizer. Malformed imports must leave subsequent updates
unchanged. Its `LibtorchAdam` reference uses libtorch's operation order.
Stock Python Adam remains a separately measured comparison; the package
does not promise bit-identical long training against its different
floating-point order.

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

`examples/custom-activation.x` trains a network through an x2c swish derivative:

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
`examples/inline-lisp.x` builds and trains a persistent model through these
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

## Not self-contained

Programs link the pinned libtorch shared libraries dynamically through an
rpath into the prepared prefix. A torch program depends on that prefix at
run time.

## Limits

- macOS arm64 CPU/MPS and Linux x86_64 CPU; no CUDA profile.
- No distributed training.
- Python optimizer interchange currently covers Adam. Other optimizers
  retain C++ archive save/load. Module state works in both directions.
- The generated operator tier is a function count, not coverage:
  `schema/README.md` names the families it leaves out. The design is in
  `plans/archive/x2c-torch.md`.
- Custom autograd currently supports one output and first-order gradients.
- `torch.compile` and TorchScript capture of x2c code are not possible:
  they capture Python. x2c runs a TorchScript model but cannot produce
  one. Agreement with Python is to float32 tolerance, not bit exact.
