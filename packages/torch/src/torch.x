/*  torch.x -- Tensors, modules, and training over libtorch, with x2c
    lifetimes and operators.

    Every record here owns one libtorch handle and is allocated with a
    Scope finalizer, so an operator temporary is released with the scope
    that created it; `free` releases a handle early. A failure inside
    libtorch raises `<bad-state>` carrying the first line of its message.
*/

#include <stdint.h>
#include "torch-2.10.h"

typedef enum Torch {
  TORCH_NAMESPACE
} Torch;

typedef enum Checkpoint {
  CHECKPOINT_NAMESPACE
} Checkpoint;

typedef struct Tensor *Tensor;
typedef struct Module *Module;
typedef struct Optimizer *Optimizer;
typedef struct Scheduler *Scheduler;

protocol Torch(T) {
  T T.add(T, T);
  T T.sub(T, T);
  T T.mul(T, T);
  T T.div(T, T);
  T T.neg(T);
  T T.matmul(T, T);
}

#pragma private

#include <string.h>

struct Tensor {
  xt_tensor native;
};

struct Module {
  xt_module native;
};

struct Optimizer {
  xt_optim native;
};

struct Scheduler {
  xt_scheduler native;
};

/* A grad-mode guard lives in the scope that installed it, so the previous
   mode is restored by Scope.release, including the release a `defer` runs
   while an Error transfers out. */
typedef struct TorchGuard *TorchGuard;

struct TorchGuard {
  int active;
};

static void _tensor_drop(void *ptr) {
  Tensor tensor = ptr;
  if (tensor.native) xt_tensor_free(tensor.native);
  tensor.native = NULL;
}

static void _module_drop(void *ptr) {
  Module module = ptr;
  if (module.native) xt_module_free(module.native);
  module.native = NULL;
}

static void _optimizer_drop(void *ptr) {
  Optimizer optimizer = ptr;
  if (optimizer.native) xt_optim_free(optimizer.native);
  optimizer.native = NULL;
}

static void _scheduler_drop(void *ptr) {
  Scheduler scheduler = ptr;
  if (scheduler.native) xt_scheduler_free(scheduler.native);
  scheduler.native = NULL;
}

/* A finalizer must not raise, so these two report nothing: an empty guard
   stack is impossible while the record exists. */
static void _no_grad_drop(void *ptr) {
  TorchGuard guard = ptr;
  if (guard.active) xt_no_grad_pop();
  guard.active = 0;
}

static void _inference_drop(void *ptr) {
  TorchGuard guard = ptr;
  if (guard.active) xt_inference_mode_pop();
  guard.active = 0;
}

static void _torch_failed(String operation) {
  String reason = String.new(xt_last_error());
  raise %(bad-state (library "torch") (operation $operation)
          (reason $reason));
}

static Tensor _wrap(xt_tensor native, String operation) {
  if (!native) _torch_failed(operation);
  Tensor tensor = Scope.malloc_finalized(sizeof(struct Tensor), _tensor_drop);
  tensor.native = native;
  return tensor;
}

static Module _wrap_module(xt_module native, String operation) {
  if (!native) _torch_failed(operation);
  Module module = Scope.malloc_finalized(sizeof(struct Module), _module_drop);
  module.native = native;
  return module;
}

static Optimizer _wrap_optimizer(xt_optim native, String operation) {
  if (!native) _torch_failed(operation);
  Optimizer optimizer =
    Scope.malloc_finalized(sizeof(struct Optimizer), _optimizer_drop);
  optimizer.native = native;
  return optimizer;
}

static Scheduler _wrap_scheduler(xt_scheduler native, String operation) {
  if (!native) _torch_failed(operation);
  Scheduler scheduler =
    Scope.malloc_finalized(sizeof(struct Scheduler), _scheduler_drop);
  scheduler.native = native;
  return scheduler;
}

static void _check(int status, String operation) {
  if (status) _torch_failed(operation);
}

static String _text(const char *native, String operation) {
  if (!native) _torch_failed(operation);
  return String.new(native);
}

/** Integer and bool dtypes carry exact values; the rest are floating. */
static int _integer_dtype(int dtype) =>
  dtype == XT_UINT8 || dtype == XT_INT8 || dtype == XT_INT16 ||
  dtype == XT_INT32 || dtype == XT_INT64 || dtype == XT_BOOL;

static int64_t *_shape(List sizes, int *rank) {
  int count = sizes.len();
  int64_t *shape = Scope.calloc(count ? count : 1, sizeof(int64_t));
  int index = 0;
  foreach (Var size, sizes) shape[index++] = size.integer();
  *rank = count;
  return shape;
}

static xt_tensor *_handles(List tensors, int *count) {
  int total = tensors.len();
  xt_tensor *handles = Scope.calloc(total ? total : 1, sizeof(xt_tensor));
  int index = 0;
  foreach (Tensor tensor, tensors) handles[index++] = tensor.native;
  *count = total;
  return handles;
}

static void _flatten(Var values, double *out, int64_t *count, int64_t limit) {
  if (values is <list>) {
    foreach (Var item, values.list()) _flatten(item, out, count, limit);
  }
  else {
    if (*count >= limit) raise %(bad-arg (library "torch")
                                 (reason "more values than the shape holds"));
    out[(*count)++] = values.convert(<f64>).double();
  }
}

static void _flatten_integers(Var values, int64_t *out, int64_t *count,
                              int64_t limit) {
  if (values is <list>) {
    foreach (Var item, values.list())
      _flatten_integers(item, out, count, limit);
  }
  else {
    if (*count >= limit) raise %(bad-arg (library "torch")
                                 (reason "more values than the shape holds"));
    out[(*count)++] = values.integer();
  }
}

static void _expect_filled(int64_t count, int64_t total) {
  if (count != total) raise %(bad-arg (library "torch")
                              (reason "fewer values than the shape holds"));
}

#pragma public

/** Copies `values`, a List of numbers or nested Lists of rows, into a new
    tensor of `shape` and `dtype`. An integer dtype collects the values as
    int64, so a value beyond a double's exact range survives. */
Tensor Tensor.of(List values, List shape, int dtype) {
  int rank;
  int64_t *sizes = _shape(shape, &rank), total = 1, count = 0;
  for (int i = 0; i < rank; i++) total *= sizes[i];
  if (_integer_dtype(dtype)) {
    int64_t *whole = Scope.calloc(total ? total : 1, sizeof(int64_t));
    _flatten_integers(values, whole, &count, total);
    _expect_filled(count, total);
    return _wrap(xt_from_int64s(whole, sizes, rank, dtype), "of");
  }
  double *data = Scope.calloc(total ? total : 1, sizeof(double));
  _flatten(values, data, &count, total);
  _expect_filled(count, total);
  return _wrap(xt_from_doubles(data, sizes, rank, dtype), "of");
}

/** Wraps one number as a zero-dimensional tensor. */
Tensor Tensor.scalar(double value, int dtype) =>
  _wrap(xt_scalar(value, dtype), "scalar");

/** Wraps one integer as a zero-dimensional tensor without going through a
    double, so values beyond 2^53 stay exact. */
Tensor Tensor.scalar_integer(long value, int dtype) =>
  _wrap(xt_scalar_int64(value, dtype), "scalar_integer");

/** A float64 zero-dimensional tensor, so `2.0 * t` reads as on scalars. */
Tensor double.tensor(double value) => Tensor.scalar(value, XT_FLOAT64);

/** An int64 zero-dimensional tensor, so `2 * t` stays exact and libtorch
    promotes it to the other operand's dtype. */
Tensor long.tensor(long value) => Tensor.scalar_integer(value, XT_INT64);

/** The same for an ordinary int literal. */
Tensor int.tensor(int value) => Tensor.scalar_integer(value, XT_INT64);

Tensor Tensor.zeros(List shape, int dtype) {
  int rank;
  int64_t *sizes = _shape(shape, &rank);
  return _wrap(xt_zeros(sizes, rank, dtype), "zeros");
}

Tensor Tensor.ones(List shape, int dtype) {
  int rank;
  int64_t *sizes = _shape(shape, &rank);
  return _wrap(xt_ones(sizes, rank, dtype), "ones");
}

Tensor Tensor.full(List shape, double value, int dtype) {
  int rank;
  int64_t *sizes = _shape(shape, &rank);
  return _wrap(xt_full(sizes, rank, value, dtype), "full");
}

Tensor Tensor.rand(List shape, int dtype) {
  int rank;
  int64_t *sizes = _shape(shape, &rank);
  return _wrap(xt_rand(sizes, rank, dtype), "rand");
}

Tensor Tensor.randn(List shape, int dtype) {
  int rank;
  int64_t *sizes = _shape(shape, &rank);
  return _wrap(xt_randn(sizes, rank, dtype), "randn");
}

Tensor Tensor.arange(double start, double end, double step, int dtype) =>
  _wrap(xt_arange(start, end, step, dtype), "arange");

/** A random permutation of `0 .. n-1` as an int64 tensor, the index source
    for shuffling a dataset. */
Tensor Torch.randperm(long n) => _wrap(xt_randperm(n), "randperm");

/** Seeds libtorch's default generator for reproducible `rand`/`randn`. */
void Torch.manual_seed(long seed) {
  _check(xt_manual_seed(seed), "manual_seed");
}

/** Pins the intra-op thread pool size. */
void Torch.set_num_threads(int count) {
  _check(xt_set_num_threads(count), "set_num_threads");
}

int Torch.num_threads(void) {
  int count;
  _check(xt_get_num_threads(&count), "num_threads");
  return count;
}

/** The pinned libtorch version string. */
String Torch.version(void) => String.new(xt_version());

/* Queries */

int Tensor.rank(Tensor t) {
  int rank;
  _check(xt_rank(t.native, &rank), "rank");
  return rank;
}

long Tensor.size(Tensor t, int dim) {
  int64_t size;
  _check(xt_size(t.native, dim, &size), "size");
  return size;
}

/** The sizes of every dimension as a List of integers. */
List Tensor.shape(Tensor t) {
  List shape = %();
  for (int dim = 0; dim < t.rank(); dim++) {
    long size = t.size(dim);
    shape = shape.append(%($size));
  }
  return shape;
}

long Tensor.numel(Tensor t) {
  int64_t count;
  _check(xt_numel(t.native, &count), "numel");
  return count;
}

int Tensor.dtype(Tensor t) {
  int dtype;
  _check(xt_dtype(t.native, &dtype), "dtype");
  return dtype;
}

int Tensor.requires_grad(Tensor t) {
  int on;
  _check(xt_requires_grad(t.native, &on), "requires_grad");
  return on;
}

int Tensor.is_leaf(Tensor t) {
  int leaf;
  _check(xt_is_leaf(t.native, &leaf), "is_leaf");
  return leaf;
}

/** The one value of a single-element tensor, tagged by the tensor's dtype:
    `<long>` for an integer or bool tensor and `<f64>` for a floating one.
    `t.item().double()` is the usual spelling where a double is wanted. */
Var Tensor.item(Tensor t) {
  if (t.numel() != 1) raise %(bad-arg (library "torch")
                              (reason "item needs one element"));
  if (_integer_dtype(t.dtype())) {
    int64_t whole;
    _check(xt_item_int64(t.native, &whole), "item");
    return whole;
  }
  double value;
  _check(xt_item_double(t.native, &value), "item");
  return value;
}

/** Every element, in row-major order, as an Array of Vars tagged by the
    tensor's dtype. */
Array Tensor.to_values(Tensor t) {
  int64_t count = t.numel();
  Array values = %[];
  if (_integer_dtype(t.dtype())) {
    int64_t *whole = Scope.calloc(count ? count : 1, sizeof(int64_t));
    _check(xt_copy_out_int64s(t.native, whole, count), "to_values");
    for (int64_t i = 0; i < count; i++) values.push(whole[i]);
    return values;
  }
  double *out = Scope.calloc(count ? count : 1, sizeof(double));
  _check(xt_copy_out_doubles(t.native, out, count), "to_values");
  for (int64_t i = 0; i < count; i++) values.push(out[i]);
  return values;
}

/** libtorch's own printed form. */
String Tensor.str(Tensor t) => _text(xt_str(t.native), "str");

/** The raw handle, for the C ABI in torch-2.10.h. */
xt_tensor Tensor.native(Tensor t) => t.native;

/** Takes ownership of a handle a raw call just produced, so the result is
    released with the scope that created it. A NULL `native` means the call
    failed and raises `<bad-state>` naming `operation`. The generated
    bindings in torch-ops.x reach handles this way. */
Tensor Tensor.adopt(xt_tensor native, String operation) =>
  _wrap(native, operation);

/** Raises `<bad-state>` naming `operation` when a raw call reported a
    nonzero status. */
void Torch.check(int status, String operation) { _check(status, operation); }

/* Arithmetic */

Tensor Tensor.add(Tensor a, Tensor b) =>
  _wrap(xt_add(a.native, b.native), "add");
Tensor Tensor.sub(Tensor a, Tensor b) =>
  _wrap(xt_sub(a.native, b.native), "sub");
Tensor Tensor.mul(Tensor a, Tensor b) =>
  _wrap(xt_mul(a.native, b.native), "mul");
Tensor Tensor.div(Tensor a, Tensor b) =>
  _wrap(xt_div(a.native, b.native), "div");
Tensor Tensor.matmul(Tensor a, Tensor b) =>
  _wrap(xt_matmul(a.native, b.native), "matmul");
Tensor Tensor.neg(Tensor a) => _wrap(xt_neg(a.native), "neg");
Tensor Tensor.pow(Tensor a, double exponent) =>
  _wrap(xt_pow(a.native, exponent), "pow");
Tensor Tensor.abs(Tensor a) => _wrap(xt_abs(a.native), "abs");
Tensor Tensor.exp(Tensor a) => _wrap(xt_exp(a.native), "exp");
Tensor Tensor.log(Tensor a) => _wrap(xt_log(a.native), "log");
Tensor Tensor.sqrt(Tensor a) => _wrap(xt_sqrt(a.native), "sqrt");
Tensor Tensor.tanh(Tensor a) => _wrap(xt_tanh(a.native), "tanh");
Tensor Tensor.sigmoid(Tensor a) => _wrap(xt_sigmoid(a.native), "sigmoid");
Tensor Tensor.relu(Tensor a) => _wrap(xt_relu(a.native), "relu");
Tensor Tensor.sum(Tensor a) => _wrap(xt_sum(a.native), "sum");
Tensor Tensor.mean(Tensor a) => _wrap(xt_mean(a.native), "mean");
Tensor Tensor.max(Tensor a) => _wrap(xt_max_all(a.native), "max");
Tensor Tensor.min(Tensor a) => _wrap(xt_min_all(a.native), "min");
Tensor Tensor.sum_dim(Tensor a, int dim, int keepdim) =>
  _wrap(xt_sum_dim(a.native, dim, keepdim), "sum_dim");
Tensor Tensor.mean_dim(Tensor a, int dim, int keepdim) =>
  _wrap(xt_mean_dim(a.native, dim, keepdim), "mean_dim");
/** The index of the largest value along `dim`, as an int64 tensor. */
Tensor Tensor.argmax(Tensor a, int dim, int keepdim) =>
  _wrap(xt_argmax(a.native, dim, keepdim), "argmax");
Tensor Tensor.softmax(Tensor a, int dim) =>
  _wrap(xt_softmax(a.native, dim), "softmax");
Tensor Tensor.log_softmax(Tensor a, int dim) =>
  _wrap(xt_log_softmax(a.native, dim), "log_softmax");

/* Losses */

Tensor Tensor.mse_loss(Tensor input, Tensor target) =>
  _wrap(xt_mse_loss(input.native, target.native), "mse_loss");
/** Softmax cross entropy over `logits`; `targets` holds int64 class
    indexes, one per row. */
Tensor Tensor.cross_entropy(Tensor logits, Tensor targets) =>
  _wrap(xt_cross_entropy(logits.native, targets.native), "cross_entropy");
/** Negative log likelihood over already log-softmaxed values. */
Tensor Tensor.nll_loss(Tensor log_probabilities, Tensor targets) =>
  _wrap(xt_nll_loss(log_probabilities.native, targets.native), "nll_loss");
Tensor Tensor.bce_with_logits(Tensor logits, Tensor targets) =>
  _wrap(xt_bce_with_logits(logits.native, targets.native),
        "bce_with_logits");

int Tensor.allclose(Tensor a, Tensor b, double rtol, double atol) {
  int close;
  _check(xt_allclose(a.native, b.native, rtol, atol, &close), "allclose");
  return close;
}

int Tensor.equal(Tensor a, Tensor b) {
  int same;
  _check(xt_equal(a.native, b.native, &same), "equal");
  return same;
}

/* Comparison and selection; a comparison produces a bool tensor. */

Tensor Tensor.eq(Tensor a, Tensor b) => _wrap(xt_eq(a.native, b.native), "eq");
Tensor Tensor.gt(Tensor a, Tensor b) => _wrap(xt_gt(a.native, b.native), "gt");
Tensor Tensor.lt(Tensor a, Tensor b) => _wrap(xt_lt(a.native, b.native), "lt");
Tensor Tensor.to_bool(Tensor a) => _wrap(xt_to_bool(a.native), "to_bool");
/** The elements where `mask` is true, flattened into one dimension. */
Tensor Tensor.masked_select(Tensor a, Tensor mask) =>
  _wrap(xt_masked_select(a.native, mask.native), "masked_select");
/** `a` where `condition` is true and `b` elsewhere. */
Tensor Tensor.where(Tensor condition, Tensor a, Tensor b) =>
  _wrap(xt_where(condition.native, a.native, b.native), "where");

/* Shape and indexing; results view the same storage. */

Tensor Tensor.reshape(Tensor a, List shape) {
  int rank;
  int64_t *sizes = _shape(shape, &rank);
  return _wrap(xt_reshape(a.native, sizes, rank), "reshape");
}
Tensor Tensor.transpose(Tensor a, int dim0, int dim1) =>
  _wrap(xt_transpose(a.native, dim0, dim1), "transpose");
/** The matrix transpose of a two-dimensional tensor. */
Tensor Tensor.t(Tensor a) => a.transpose(0, 1);
Tensor Tensor.squeeze(Tensor a, int dim) =>
  _wrap(xt_squeeze(a.native, dim), "squeeze");
Tensor Tensor.unsqueeze(Tensor a, int dim) =>
  _wrap(xt_unsqueeze(a.native, dim), "unsqueeze");
Tensor Tensor.select(Tensor a, int dim, long index) =>
  _wrap(xt_select(a.native, dim, index), "select");
Tensor Tensor.slice(Tensor a, int dim, long start, long end, long step) =>
  _wrap(xt_slice(a.native, dim, start, end, step), "slice");
/** `length` entries of `dim` starting at `start`. */
Tensor Tensor.narrow(Tensor a, int dim, long start, long length) =>
  _wrap(xt_narrow(a.native, dim, start, length), "narrow");
Tensor Tensor.flatten(Tensor a, int start, int end) =>
  _wrap(xt_flatten(a.native, start, end), "flatten");
Tensor Tensor.index_select(Tensor a, int dim, Tensor indexes) =>
  _wrap(xt_index_select(a.native, dim, indexes.native), "index_select");

/** Joins `tensors` along an existing dimension. */
Tensor Tensor.cat(List tensors, int dim) {
  int count;
  xt_tensor *handles = _handles(tensors, &count);
  return _wrap(xt_cat(handles, count, dim), "cat");
}

/** Joins `tensors` along a new dimension `dim`. */
Tensor Tensor.stack(List tensors, int dim) {
  int count;
  xt_tensor *handles = _handles(tensors, &count);
  return _wrap(xt_stack(handles, count, dim), "stack");
}

Tensor Tensor.to_dtype(Tensor a, int dtype) =>
  _wrap(xt_to_dtype(a.native, dtype), "to_dtype");
Tensor Tensor.clone(Tensor a) => _wrap(xt_clone(a.native), "clone");
Tensor Tensor.contiguous(Tensor a) =>
  _wrap(xt_contiguous(a.native), "contiguous");

/** `t[key]` reads three ways: an integer selects along the first
    dimension as in PyTorch, a bool `Tensor` selects the masked elements,
    and a List of integers selects each dimension in turn, so
    `t[%(1 2)]` is `t.select(0, 1).select(0, 2)`. */
Tensor Tensor.getindex(Tensor a, Var key) {
  if (key is Tensor) return a.masked_select(key.tensor());
  if (key is <list>) {
    Tensor value = a;
    foreach (Var index, key.list()) value = value.select(0, index.integer());
    return value;
  }
  return a.select(0, key.integer());
}

/* Autograd */

/** Marks `a` as a leaf that accumulates a gradient and returns it. */
Tensor Tensor.requires_grad_(Tensor a, int on) =>
  _wrap(xt_requires_grad_(a.native, on), "requires_grad_");
Tensor Tensor.detach(Tensor a) => _wrap(xt_detach(a.native), "detach");
void Tensor.backward(Tensor a) { _check(xt_backward(a.native), "backward"); }
/** The accumulated gradient; raises when none has been computed. */
Tensor Tensor.grad(Tensor a) => _wrap(xt_grad(a.native), "grad");
void Tensor.zero_grad(Tensor a) {
  _check(xt_zero_grad(a.native), "zero_grad");
}
/** `a += alpha * b` in place, the update step of gradient descent. */
Tensor Tensor.add_(Tensor a, Tensor b, double alpha) {
  _check(xt_add_(a.native, b.native, alpha), "add_");
  return a;
}
/** Copies `src` into `a` in place, ignoring gradient recording, so a
    parameter can be overwritten from a checkpoint. */
Tensor Tensor.copy_(Tensor a, Tensor src) {
  _check(xt_copy_(a.native, src.native), "copy_");
  return a;
}

/** Disables gradient recording until the active scope is released. The
    idiom is a retained scope with `defer Scope.release()`, so the previous
    mode returns whether the scope ends normally or an Error transfers out
    of it. */
void Torch.no_grad(void) {
  TorchGuard guard =
    Scope.malloc_finalized(sizeof(struct TorchGuard), _no_grad_drop);
  guard.active = 0;
  _check(xt_no_grad_push(), "no_grad");
  guard.active = 1;
}

/** Stronger than `no_grad`: results carry no autograd metadata at all.
    Scoped the same way. */
void Torch.inference_mode(void) {
  TorchGuard guard =
    Scope.malloc_finalized(sizeof(struct TorchGuard), _inference_drop);
  guard.active = 0;
  _check(xt_inference_mode_push(), "inference_mode");
  guard.active = 1;
}

int Torch.grad_enabled(void) {
  int enabled;
  _check(xt_grad_enabled(&enabled), "grad_enabled");
  return enabled;
}

/** Releases the libtorch handle now; the record's finalizer then does
    nothing. Returns NULL for the adjacent-defer form. */
Tensor Tensor.free(Tensor a) {
  _tensor_drop(a);
  return NULL;
}

/* Modules.

   A Module owns a libtorch module handle. `Module.composed()` is a root
   with no forward of its own: register children under it by name and
   write the forward in x2c. Parameter and buffer names are the qualified
   names Python's state_dict() uses.
*/

/** A fully connected layer with a bias, `y = x @ w.t() + b`. */
Module Module.linear(long in_features, long out_features) =>
  _wrap_module(xt_linear_new(in_features, out_features, 1), "linear");

/** A fully connected layer whose bias is optional. */
Module Module.linear_bias(long in_features, long out_features, int bias) =>
  _wrap_module(xt_linear_new(in_features, out_features, bias),
               "linear_bias");

/** A root that owns named children; its forward is ordinary x2c code. */
Module Module.composed(void) => _wrap_module(xt_composed_new(), "composed");

/** Registers `child` under `name` and returns it, so a declaration reads
    `Module first = model.register("l1", Module.linear(4, 8));`. */
Module Module.register(Module parent, String name, Module child) {
  _check(xt_module_register_module(parent.native, name, child.native),
         "register");
  return child;
}

/** Registers `value` as a parameter of `parent` and returns it. */
Tensor Module.register_parameter(Module parent, String name, Tensor value,
                                 int requires_grad) {
  _check(xt_module_register_parameter(parent.native, name, value.native,
                                      requires_grad),
         "register_parameter");
  return value;
}

/** Registers `value` as a buffer: saved and moved with the module, but not
    trained. */
Tensor Module.register_buffer(Module parent, String name, Tensor value) {
  _check(xt_module_register_buffer(parent.native, name, value.native),
         "register_buffer");
  return value;
}

/** A second handle onto the child registered under `name`; freeing it does
    not detach the child. */
Module Module.child(Module parent, String name) =>
  _wrap_module(xt_module_child(parent.native, name), "child");

/** Runs a native forward, such as a Linear's. A composed module has no
    native forward and raises. */
Tensor Module.forward(Module m, Tensor input) =>
  _wrap(xt_module_forward(m.native, input.native), "forward");

/** Every trainable parameter, including those of children, as a List of
    Tensor. */
List Module.parameters(Module m) {
  int64_t count;
  _check(xt_module_parameter_count(m.native, &count), "parameters");
  List values = %();
  for (int64_t i = 0; i < count; i++) {
    Tensor parameter = _wrap(xt_module_parameter(m.native, i), "parameters");
    values = values.append(%($parameter));
  }
  return values;
}

/** Every parameter as a `(name tensor)` pair, in libtorch's order. */
List Module.named_parameters(Module m) {
  int64_t count;
  _check(xt_module_parameter_count(m.native, &count), "named_parameters");
  List values = %();
  for (int64_t i = 0; i < count; i++) {
    String name = _text(xt_module_parameter_name(m.native, i),
                        "named_parameters");
    Tensor parameter =
      _wrap(xt_module_parameter(m.native, i), "named_parameters");
    values = values.append(%(($name $parameter)));
  }
  return values;
}

/** Every buffer, including those of children, as a List of Tensor. */
List Module.buffers(Module m) {
  int64_t count;
  _check(xt_module_buffer_count(m.native, &count), "buffers");
  List values = %();
  for (int64_t i = 0; i < count; i++) {
    Tensor buffer = _wrap(xt_module_buffer(m.native, i), "buffers");
    values = values.append(%($buffer));
  }
  return values;
}

/** Every buffer as a `(name tensor)` pair. */
List Module.named_buffers(Module m) {
  int64_t count;
  _check(xt_module_buffer_count(m.native, &count), "named_buffers");
  List values = %();
  for (int64_t i = 0; i < count; i++) {
    String name = _text(xt_module_buffer_name(m.native, i), "named_buffers");
    Tensor buffer = _wrap(xt_module_buffer(m.native, i), "named_buffers");
    values = values.append(%(($name $buffer)));
  }
  return values;
}

void Module.train(Module m) { _check(xt_module_train(m.native, 1), "train"); }
void Module.eval(Module m) { _check(xt_module_train(m.native, 0), "eval"); }

int Module.is_training(Module m) {
  int training;
  _check(xt_module_is_training(m.native, &training), "is_training");
  return training;
}

void Module.zero_grad(Module m) {
  _check(xt_module_zero_grad(m.native), "zero_grad");
}

/** Converts every parameter and buffer in place. */
void Module.to_dtype(Module m, int dtype) {
  _check(xt_module_to_dtype(m.native, dtype), "to_dtype");
}

/** Writes the parameters and buffers as a pickled name-to-tensor dict.
    Python reads it with `torch.load`. */
void Module.save(Module m, String path) {
  _check(xt_module_save_pickle(m.native, path), "save");
}

/** Reads a pickled name-to-tensor dict into this module. Every parameter
    and buffer name must be present; a missing one raises. */
void Module.load(Module m, String path) {
  _check(xt_module_load_pickle(m.native, path), "load");
}

/** Writes a libtorch serialization archive. Python reads it only through
    `torch.jit.load`. */
void Module.save_archive(Module m, String path) {
  _check(xt_module_save_archive(m.native, path), "save_archive");
}

void Module.load_archive(Module m, String path) {
  _check(xt_module_load_archive(m.native, path), "load_archive");
}

xt_module Module.native(Module m) => m.native;

Module Module.free(Module m) {
  _module_drop(m);
  return NULL;
}

/* Optimizers.

   An optimizer refers to the parameter tensors it was built over, so the
   module must outlive it.
*/

Optimizer Optimizer.sgd(Module m, double lr) =>
  _wrap_optimizer(xt_sgd_new(m.native, lr, 0.0, 0.0, 0), "sgd");

Optimizer Optimizer.sgd_momentum(Module m, double lr, double momentum,
                                 double weight_decay) =>
  _wrap_optimizer(xt_sgd_new(m.native, lr, momentum, weight_decay, 0),
                  "sgd_momentum");

Optimizer Optimizer.adam(Module m, double lr) =>
  _wrap_optimizer(xt_adam_new(m.native, lr, 0.9, 0.999, 1e-8, 0.0, 0),
                  "adam");

Optimizer Optimizer.adam_with(Module m, double lr, double beta1,
                              double beta2, double eps, double weight_decay,
                              int amsgrad) =>
  _wrap_optimizer(xt_adam_new(m.native, lr, beta1, beta2, eps, weight_decay,
                              amsgrad),
                  "adam_with");

Optimizer Optimizer.adamw(Module m, double lr) =>
  _wrap_optimizer(xt_adamw_new(m.native, lr, 0.9, 0.999, 1e-8, 0.01, 0),
                  "adamw");

Optimizer Optimizer.rmsprop(Module m, double lr) =>
  _wrap_optimizer(xt_rmsprop_new(m.native, lr, 0.99, 1e-8, 0.0, 0.0),
                  "rmsprop");

Optimizer Optimizer.adagrad(Module m, double lr) =>
  _wrap_optimizer(xt_adagrad_new(m.native, lr, 0.0), "adagrad");

/** An optimizer over loose parameter tensors rather than a module. `kind`
    is one of the XT_SGD .. XT_ADAGRAD constants. */
Optimizer Optimizer.over(List tensors, int kind, double lr) {
  int count;
  xt_tensor *handles = _handles(tensors, &count);
  return _wrap_optimizer(xt_optim_new_from_tensors(kind, handles, count, lr),
                         "over");
}

void Optimizer.zero_grad(Optimizer o) {
  _check(xt_optim_zero_grad(o.native), "zero_grad");
}

void Optimizer.step(Optimizer o) { _check(xt_optim_step(o.native), "step"); }

/** The learning rate of the first parameter group. */
double Optimizer.lr(Optimizer o) {
  double lr;
  _check(xt_optim_lr(o.native, &lr), "lr");
  return lr;
}

/** Sets the learning rate of every parameter group. */
void Optimizer.set_lr(Optimizer o, double lr) {
  _check(xt_optim_set_lr(o.native, lr), "set_lr");
}

/** Writes the optimizer state as a libtorch archive. This format is for
    resuming in x2c or C++; Python does not read it. */
void Optimizer.save(Optimizer o, String path) {
  _check(xt_optim_save(o.native, path), "save");
}

void Optimizer.load(Optimizer o, String path) {
  _check(xt_optim_load(o.native, path), "load");
}

xt_optim Optimizer.native(Optimizer o) => o.native;

Optimizer Optimizer.free(Optimizer o) {
  _optimizer_drop(o);
  return NULL;
}

/* Learning-rate schedules; a Scheduler refers to its optimizer. */

/** Multiplies the learning rate by `gamma` every `step_size` calls to
    `step`. */
Scheduler Scheduler.step_lr(Optimizer o, int step_size, double gamma) =>
  _wrap_scheduler(xt_step_lr_new(o.native, step_size, gamma), "step_lr");

/** Multiplies the learning rate by `factor` once `patience` calls to
    `step_metric` pass without improvement. `mode_min` treats a smaller
    metric as better. */
Scheduler Scheduler.reduce_on_plateau(Optimizer o, int mode_min,
                                      double factor, int patience,
                                      double threshold, int cooldown,
                                      double min_lr) =>
  _wrap_scheduler(xt_reduce_on_plateau_new(o.native, mode_min, factor,
                                           patience, threshold, cooldown,
                                           min_lr),
                  "reduce_on_plateau");

void Scheduler.step(Scheduler s) {
  _check(xt_scheduler_step(s.native), "step");
}

void Scheduler.step_metric(Scheduler s, double metric) {
  _check(xt_scheduler_step_metric(s.native, metric), "step_metric");
}

xt_scheduler Scheduler.native(Scheduler s) => s.native;

Scheduler Scheduler.free(Scheduler s) {
  _scheduler_drop(s);
  return NULL;
}

/* Checkpoints.

   The package format is one pickled dict of name to tensor, the same file
   `Module.save` writes. Python reads it with `torch.load` and writes it
   with `torch.save(dict(model.state_dict()), path)`.
*/

/** Writes a Map of String name to Tensor. */
void Checkpoint.save(Map values, String path) {
  int count = values.len();
  const char **names = Scope.calloc(count ? count : 1, sizeof(char *));
  xt_tensor *handles = Scope.calloc(count ? count : 1, sizeof(xt_tensor));
  int index = 0;
  foreach (Var (name, value), values) {
    names[index] = name.str();
    handles[index] = value.tensor().native;
    index++;
  }
  _check(xt_tensors_save_pickle(names, handles, count, path),
         "checkpoint save");
}

/** Reads a pickled dict as a Map of String name to Tensor. */
Map Checkpoint.load(String path) {
  xt_pickle opened = xt_pickle_open(path);
  if (!opened) _torch_failed("checkpoint load");
  defer xt_pickle_free(opened);
  int64_t count;
  _check(xt_pickle_count(opened, &count), "checkpoint load");
  Map values = %{};
  for (int64_t i = 0; i < count; i++) {
    String name = _text(xt_pickle_name(opened, i), "checkpoint load");
    Tensor value = _wrap(xt_pickle_tensor(opened, i), "checkpoint load");
    values[name] = value;
  }
  return values;
}

Var Tensor.var(Tensor t) => Var.new(<torch--ten>, t);
Tensor Var.tensor(Var value) => (Tensor) value.pointer();

Var Module.var(Module m) => Var.new(<torch--mod>, m);
Module Var.module(Var value) => (Module) value.pointer();

Var Optimizer.var(Optimizer o) => Var.new(<torch--opt>, o);
Optimizer Var.optimizer(Var value) => (Optimizer) value.pointer();

Var Scheduler.var(Scheduler s) => Var.new(<torch--sch>, s);
Scheduler Var.scheduler(Var value) => (Scheduler) value.pointer();

protocol Torch(Tensor);
protocol Var(Tensor);
protocol Var(Module);
protocol Var(Optimizer);
protocol Var(Scheduler);

/* The generated operator bindings are a second unit of this package; the
   include puts them in the public header an `import "torch"` reads. */
#include "torch-ops.x"
