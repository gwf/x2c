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

typedef enum TorchLisp {
  TORCHLISP_NAMESPACE
} TorchLisp;

typedef enum Checkpoint {
  CHECKPOINT_NAMESPACE
} Checkpoint;

typedef struct Tensor *Tensor;
typedef struct Module *Module;
typedef struct Optimizer *Optimizer;
typedef struct Scheduler *Scheduler;
typedef struct JitModule *JitModule;

/** Callback-only context for saving native tensors for differentiation. */
typedef xt_autograd_context AutogradContext;

protocol Torch(T) {
  T T.add(T, T);
  T T.sub(T, T);
  T T.mul(T, T);
  T T.div(T, T);
  T T.neg(T);
  T T.matmul(T, T);
  void T.discard(T);
}

#pragma private

#include <math.h>
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

/* A schedule libtorch ships holds a native object; the rest are
   arithmetic over the optimizer's rate, computed from the step count. */
#define SCHEDULE_NATIVE 0
#define SCHEDULE_COSINE 1
#define SCHEDULE_WARMUP 2
#define SCHEDULE_MULTISTEP 3

struct Scheduler {
  xt_scheduler native;
  Optimizer optimizer;
  int kind;
  long steps;
  double base_lr;
  double gamma;
  double eta_min;
  long span;
  List milestones;
};

struct JitModule {
  xt_jit_module native;
};

/* A grad-mode guard lives in the scope that installed it, so the previous
   mode is restored by Scope.release, including the release a `defer` runs
   while an Error transfers out. */
typedef struct TorchGuard *TorchGuard;

struct TorchGuard {
  int active;
};

typedef struct TorchCallbackError {
  Symbol cause;
  List detail;
} TorchCallbackError;

static threaded TorchCallbackError *callback_error;

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

static void _jit_drop(void *ptr) {
  JitModule module = ptr;
  if (module.native) xt_jit_free(module.native);
  module.native = NULL;
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

static JitModule _wrap_jit(xt_jit_module native, String operation) {
  if (!native) _torch_failed(operation);
  JitModule module =
    Scope.malloc_finalized(sizeof(struct JitModule), _jit_drop);
  module.native = native;
  return module;
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
  foreach (Var size, sizes) {
    long extent = size;  // converting; a Symbol or text raises
    shape[index++] = extent;
  }
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
    long exact = values;
    out[(*count)++] = exact;
  }
}

static void _expect_filled(int64_t count, int64_t total) {
  if (count != total) raise %(bad-arg (library "torch")
                              (reason "fewer values than the shape holds"));
}

#pragma public

/** Reports whether this libtorch build can use the host's MPS device. */
int Torch.mps_available(void) {
  int available;
  _check(xt_mps_available(&available), "mps_available");
  return available;
}

/** Waits for all queued MPS kernels to finish. */
void Torch.mps_synchronize(void) {
  _check(xt_mps_synchronize(), "mps_synchronize");
}

/** Returns the native device name, such as "cpu" or "mps:0". */
String Tensor.device(Tensor tensor) {
  const char *device = xt_device(tensor.native);
  if (!device) _torch_failed("device");
  return String.new(device);
}

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

/** Pins the inter-op thread pool size. libtorch accepts this only before
    the pool starts, so call it before the first parallel operation. */
void Torch.set_num_interop_threads(int count) {
  _check(xt_set_num_interop_threads(count), "set_num_interop_threads");
}

int Torch.num_interop_threads(void) {
  int count;
  _check(xt_get_num_interop_threads(&count), "num_interop_threads");
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
    foreach (Var index, key.list()) {
      long position = index;
      value = value.select(0, position);
    }
    return value;
  }
  long position = key;
  return a.select(0, position);
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

/** Releases the handle of an unnamed operator temporary. The compiler
    calls this on a value it made for one operator, such as `a * b` inside
    `a * b + c`, right after that operator has used it, so a chain of
    operators keeps only its inputs and its result alive. */
void Tensor.discard(Tensor a) { _tensor_drop(a); }

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

/** A root that forwards its children in the order they were pushed, the
    same composition as PyTorch's `nn.Sequential`. */
Module Module.sequential(void) =>
  _wrap_module(xt_sequential_new(), "sequential");

/** Appends `child` to a sequential root under its position as a name,
    "0", "1", and so on, as PyTorch names them, and returns it. */
Module Module.push(Module sequence, Module child) {
  int64_t count;
  _check(xt_module_child_count(sequence.native, &count), "push");
  long position = count;
  return sequence.register(%"$position", child);
}

/** A 1-D convolution with unit stride, no padding, unit dilation, one
    group, and a bias. */
Module Module.conv1d(long in_channels, long out_channels, long kernel) =>
  _wrap_module(xt_conv1d_new(in_channels, out_channels, kernel, 1, 0, 1, 1,
                             1),
               "conv1d");

/** A 1-D convolution with every option PyTorch's constructor takes. */
Module Module.conv1d_with(long in_channels, long out_channels, long kernel,
                          long stride, long padding, long dilation,
                          long groups, int bias) =>
  _wrap_module(xt_conv1d_new(in_channels, out_channels, kernel, stride,
                             padding, dilation, groups, bias),
               "conv1d_with");

/** A 2-D convolution with unit stride, no padding, unit dilation, one
    group, and a bias. Input is `batch x channels x height x width`. */
Module Module.conv2d(long in_channels, long out_channels, long kernel) =>
  _wrap_module(xt_conv2d_new(in_channels, out_channels, kernel, 1, 0, 1, 1,
                             1),
               "conv2d");

/** A 2-D convolution with every option PyTorch's constructor takes. */
Module Module.conv2d_with(long in_channels, long out_channels, long kernel,
                          long stride, long padding, long dilation,
                          long groups, int bias) =>
  _wrap_module(xt_conv2d_new(in_channels, out_channels, kernel, stride,
                             padding, dilation, groups, bias),
               "conv2d_with");

/** Batch normalization over `features` channels of a 2-D or 3-D input,
    with PyTorch's defaults and running statistics. */
Module Module.batch_norm1d(long features) =>
  _wrap_module(xt_batch_norm1d_new(features, 1e-5, 0.1, 1, 1),
               "batch_norm1d");

Module Module.batch_norm1d_with(long features, double eps, double momentum,
                                int affine, int track_running_stats) =>
  _wrap_module(xt_batch_norm1d_new(features, eps, momentum, affine,
                                   track_running_stats),
               "batch_norm1d_with");

/** Batch normalization over `features` channels of an image batch. */
Module Module.batch_norm2d(long features) =>
  _wrap_module(xt_batch_norm2d_new(features, 1e-5, 0.1, 1, 1),
               "batch_norm2d");

Module Module.batch_norm2d_with(long features, double eps, double momentum,
                                int affine, int track_running_stats) =>
  _wrap_module(xt_batch_norm2d_new(features, eps, momentum, affine,
                                   track_running_stats),
               "batch_norm2d_with");

/** Layer normalization over the trailing dimensions `shape` names. */
Module Module.layer_norm(List shape) {
  int rank;
  int64_t *sizes = _shape(shape, &rank);
  return _wrap_module(xt_layer_norm_new(sizes, rank, 1e-5, 1),
                      "layer_norm");
}

Module Module.layer_norm_with(List shape, double eps, int affine) {
  int rank;
  int64_t *sizes = _shape(shape, &rank);
  return _wrap_module(xt_layer_norm_new(sizes, rank, eps, affine),
                      "layer_norm_with");
}

/** Zeroes each element with probability `p` while training and is the
    identity in eval, as in PyTorch. */
Module Module.dropout(double p) =>
  _wrap_module(xt_dropout_new(p), "dropout");

/** A lookup table of `num_embeddings` rows of `dim`; its input is an
    int64 tensor of row indexes. */
Module Module.embedding(long num_embeddings, long dim) =>
  _wrap_module(xt_embedding_new(num_embeddings, dim), "embedding");

/** An LSTM. `batch_first` puts the batch before the time step, and
    `Module.forward_state` runs it. */
Module Module.lstm(long input_size, long hidden_size, long layers,
                   int batch_first) =>
  _wrap_module(xt_lstm_new(input_size, hidden_size, layers, batch_first),
               "lstm");

/** A GRU, run the same way as an LSTM but with one state tensor. */
Module Module.gru(long input_size, long hidden_size, long layers,
                  int batch_first) =>
  _wrap_module(xt_gru_new(input_size, hidden_size, layers, batch_first),
               "gru");

/** Max pooling over square windows of `kernel`, stride equal to the
    kernel and no padding, as in PyTorch. */
Module Module.max_pool2d(long kernel) =>
  _wrap_module(xt_max_pool2d_new(kernel, kernel, 0), "max_pool2d");

Module Module.max_pool2d_with(long kernel, long stride, long padding) =>
  _wrap_module(xt_max_pool2d_new(kernel, stride, padding),
               "max_pool2d_with");

/** Average pooling over square windows of `kernel`. */
Module Module.avg_pool2d(long kernel) =>
  _wrap_module(xt_avg_pool2d_new(kernel, kernel, 0), "avg_pool2d");

Module Module.avg_pool2d_with(long kernel, long stride, long padding) =>
  _wrap_module(xt_avg_pool2d_new(kernel, stride, padding),
               "avg_pool2d_with");

/** Flattens every dimension from the first onward, keeping the batch. */
Module Module.flatten(void) =>
  _wrap_module(xt_flatten_new(1, -1), "flatten");

Module Module.flatten_with(long start_dim, long end_dim) =>
  _wrap_module(xt_flatten_new(start_dim, end_dim), "flatten_with");

/** The activations as modules, for a sequential model. */
Module Module.relu(void) => _wrap_module(xt_relu_new(), "relu");
Module Module.tanh(void) => _wrap_module(xt_tanh_new(), "tanh");
Module Module.sigmoid(void) => _wrap_module(xt_sigmoid_new(), "sigmoid");

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

/** Runs a recurrent layer and returns `(output hidden)` for a GRU or
    `(output hidden cell)` for an LSTM. `Module.forward` does not run
    these: they produce a state as well as a sequence. */
List Module.forward_state(Module m, Tensor input) {
  xt_tensor output = NULL, hidden = NULL, cell = NULL;
  _check(xt_rnn_forward(m.native, input.native, &output, &hidden, &cell),
         "forward_state");
  Tensor sequence = _wrap(output, "forward_state");
  Tensor state = _wrap(hidden, "forward_state");
  if (!cell) return %($sequence $state);
  Tensor memory = _wrap(cell, "forward_state");
  return %($sequence $state $memory);
}

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

/** Moves parameters and buffers to `device`. Move before constructing an
    optimizer, which retains the parameters it was built over. */
void Module.to_device(Module model, String device) {
  _check(xt_module_to_device(model.native, device), "to_device");
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

/** Writes Adam state in the dictionary format Python's optimizer loads.
    Parameter IDs follow iteration order across groups. */
void Optimizer.save_python(Optimizer optimizer, String path) {
  _check(xt_optim_save_python(optimizer.native, path), "save_python");
}

/** Loads Python Adam state, matching parameter IDs to this optimizer's
    parameters in order. Replaces groups and state after parsing succeeds.
    Numeric options import by value, including integers and scalar tensors.
    The caller supplies the same parameter order as the saved optimizer. */
void Optimizer.load_python(Optimizer optimizer, String path) {
  _check(xt_optim_load_python(optimizer.native, path), "load_python");
}

xt_optim Optimizer.native(Optimizer o) => o.native;

Optimizer Optimizer.free(Optimizer o) {
  _optimizer_drop(o);
  return NULL;
}

/* Custom functions borrow Funcs; the native graph owns saved tensor
   references. The callback Context reclaims all temporary x2c state. */
#pragma private

static Var _custom_invoke(Func function, AutogradContext context, Var value) {
  FuncArg arguments[] = { FuncArg.value(AutogradContext.var(context)),
                          FuncArg.value(value) };
  return function.apply(2, arguments);
}

static int _custom_call(void *pointer, xt_autograd_context native,
    xt_tensor *inputs, int count, int forward, int outputs) {
  Context context = NULL;
  int failed = 0;
  try {
    context = Context.open_isolated();
    Func function = pointer;
    List values = NULL;
    for (int i = count - 1; i >= 0; i--)
      values = cons(_wrap(xt_tensor_alias(inputs[i]), "custom input"), values);
    AutogradContext frame = native;
    if (forward) {
      Tensor result = _custom_invoke(function, frame, values);
      _check(xt_custom_output(native, 0, result ? result.native : NULL),
             "custom output");
    }
    else {
      Tensor gradient = values[0].tensor();
      List result = _custom_invoke(function, frame, gradient);
      if (result.len() != outputs)
        raise %(bad-arity (library "torch") (operation "custom backward"));
      for (int i = 0; i < outputs; i++) {
        Tensor tensor = result[i].is_null() ? NULL : result[i].tensor();
        _check(xt_custom_output(native, i, tensor ? tensor.native : NULL),
               "custom gradient");
      }
    }
  }
  catch %(?cause *detail): {
    failed = 1;
    callback_error->cause = cause;
    try {
      List snapshot = Error.snapshot(detail);
      callback_error->detail = context ? context.export(snapshot).list() : snapshot;
    }
    catch %(?snapcause *): {
      callback_error->cause = snapcause;
      callback_error->detail = NULL;
    }
  }
  if (context) context.close();
  return failed;
}

#pragma public

/** Applies one custom function. `forward(context, inputs)` returns a Tensor;
    `backward(context, output_gradient)` returns one Tensor or Null per input.
    Funcs and their captured referents must outlive the graph, on this thread.
    Callbacks may not mutate inputs in place or start another backward pass.
    Inference tensors have no version counters to diagnose input mutation.
    Use `backward_callbacks` to differentiate the result. */
Tensor Tensor.custom(Func forward, Func backward, List inputs) {
  TorchCallbackError error = {0};
  TorchCallbackError *previous = callback_error;
  callback_error = &error;
  defer callback_error = previous;
  int count;
  xt_tensor *handles = _handles(inputs, &count);
  xt_tensor result = xt_custom(_custom_call, forward, backward, handles, count);
  if (error.cause) Error.raise(error.cause, error.detail);
  return _wrap(result, "custom");
}

/** Differentiates a scalar on the invoking thread, including CPU and MPS
    custom callbacks. Restores autograd scheduling after success or failure.
    Nested backward and higher-order differentiation are not supported. */
void Tensor.backward_callbacks(Tensor tensor) {
  TorchCallbackError error = {0};
  TorchCallbackError *previous = callback_error;
  callback_error = &error;
  defer callback_error = previous;
  int status = xt_backward_callbacks(tensor.native);
  if (error.cause) Error.raise(error.cause, error.detail);
  _check(status, "backward_callbacks");
}

/** Saves native tensor references during forward; wrappers may be released
    after the callback. Native autograd checks subsequent in-place changes. */
void AutogradContext.save_for_backward(AutogradContext context, List tensors) {
  int count;
  xt_tensor *handles = _handles(tensors, &count);
  _check(xt_custom_save(context, handles, count), "save_for_backward");
}

/** Returns callback-owned wrappers for the saved native tensors. */
List AutogradContext.saved_tensors(AutogradContext context) {
  int count;
  _check(xt_custom_saved_count(context, &count), "saved_tensors");
  List result = NULL;
  for (int i = count - 1; i >= 0; i--)
    result = cons(_wrap(xt_custom_saved(context, i), "saved_tensors"), result);
  return result;
}

/** Reports whether differentiation needs the selected input's gradient. */
int AutogradContext.needs_input_grad(AutogradContext context, int index) {
  int needed;
  _check(xt_custom_needs_grad(context, index, &needed), "needs_input_grad");
  return needed;
}

Var AutogradContext.var(AutogradContext context) =>
  Var.new(<torch--ctx>, context);
AutogradContext Var.autogradcontext(Var value) => value.pointer();
protocol Var(AutogradContext) tag <torch--ctx>;

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

/* The schedules libtorch does not ship. Its C++ library has exactly
   StepLR and ReduceLROnPlateau, so these three are arithmetic over the
   optimizer's rate: each computes the rate from the number of completed
   `step` calls and writes it to every parameter group, starting at
   construction with no step yet taken. */

static double _schedule_rate(Scheduler s) {
  double taken = s.steps;
  if (s.kind == SCHEDULE_COSINE) {
    double span = s.span > 0 ? (double) s.span : 1.0;
    if (taken > span) taken = span;
    return s.eta_min +
      (s.base_lr - s.eta_min) * (1.0 + cos(M_PI * taken / span)) / 2.0;
  }
  if (s.kind == SCHEDULE_WARMUP) {
    double span = s.span > 0 ? (double) s.span : 1.0;
    double part = (taken + 1.0) / span;
    return s.base_lr * (part < 1.0 ? part : 1.0);
  }
  double rate = s.base_lr;
  foreach (Var milestone, s.milestones) {
    long boundary = milestone;
    if (s.steps >= boundary) rate *= s.gamma;
  }
  return rate;
}

static Scheduler _schedule(Optimizer o, int kind, double base_lr) {
  Scheduler s =
    Scope.malloc_finalized(sizeof(struct Scheduler), _scheduler_drop);
  s.native = NULL;
  s.optimizer = o;
  s.kind = kind;
  s.steps = 0;
  s.base_lr = base_lr;
  s.gamma = 1.0;
  s.eta_min = 0.0;
  s.span = 1;
  s.milestones = %();
  return s;
}

/** Anneals the rate from the optimizer's current one down to `eta_min`
    over `t_max` steps, following a half cosine. */
Scheduler Scheduler.cosine(Optimizer o, long t_max, double eta_min) {
  Scheduler s = _schedule(o, SCHEDULE_COSINE, o.lr());
  s.span = t_max;
  s.eta_min = eta_min;
  o.set_lr(_schedule_rate(s));
  return s;
}

/** Raises the rate linearly from `base_lr / warmup_steps` to `base_lr`
    over `warmup_steps` steps and holds it there. */
Scheduler Scheduler.linear_warmup(Optimizer o, long warmup_steps,
                                  double base_lr) {
  Scheduler s = _schedule(o, SCHEDULE_WARMUP, base_lr);
  s.span = warmup_steps;
  o.set_lr(_schedule_rate(s));
  return s;
}

/** Multiplies the rate by `gamma` once for each milestone step count
    reached, as PyTorch's MultiStepLR does. The List is held, not copied,
    so it must outlive the schedule as the optimizer does. */
Scheduler Scheduler.multistep(Optimizer o, List milestones, double gamma) {
  Scheduler s = _schedule(o, SCHEDULE_MULTISTEP, o.lr());
  s.milestones = milestones;
  s.gamma = gamma;
  o.set_lr(_schedule_rate(s));
  return s;
}

/** Advances the schedule one step. */
void Scheduler.step(Scheduler s) {
  if (!s.native) {
    s.steps++;
    s.optimizer.set_lr(_schedule_rate(s));
    return;
  }
  _check(xt_scheduler_step(s.native), "step");
}

/** Advances a plateau schedule with the metric it watches. */
void Scheduler.step_metric(Scheduler s, double metric) {
  if (!s.native) raise %(bad-state (library "torch")
                         (operation "step_metric")
                         (reason "this schedule advances without a metric"));
  _check(xt_scheduler_step_metric(s.native, metric), "step_metric");
}

/** The number of `step` calls an x2c schedule has taken. */
long Scheduler.steps(Scheduler s) => s.steps;

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

/* Datasets.

   libtorch's own DataLoader is a template over a compile-time Dataset
   concept and cannot cross a C ABI, so batching is x2c: `Torch.randperm`
   and `Tensor.index_select` over the two tensors a dataset returns.
*/

/** Reads the four MNIST IDX files under `root` as `(images targets)`: an
    N x 1 x 28 x 28 float32 tensor scaled to [0, 1] and N int64 classes.
    `train` chooses the 60,000-row training set over the 10,000-row test
    set. A missing or malformed file raises `<bad-state>`. */
List Torch.mnist(String root, int train) {
  xt_tensor images = NULL, targets = NULL;
  _check(xt_mnist_load(root, train, &images, &targets), "mnist");
  Tensor x = _wrap(images, "mnist");
  Tensor y = _wrap(targets, "mnist");
  return %($x $y);
}

/* TorchScript.

   x2c runs a module Python scripted or traced; it cannot produce one.
   Inputs and results cross as tensors.
*/

/** Loads a TorchScript file saved by Python's `torch.jit.save`. A file
    that is not TorchScript raises `<bad-state>`. */
JitModule JitModule.load(String path) =>
  _wrap_jit(xt_jit_load(path), "jit load");

/** Runs the module's forward over a List of Tensor and returns its
    results as a List of Tensor: one entry for a tensor result and one
    per element for a tuple of tensors. */
List JitModule.forward(JitModule m, List inputs) {
  int count;
  xt_tensor *handles = _handles(inputs, &count);
  /* A forward returning more tensors than this reports as a failure
     rather than a truncated List. */
  int limit = 16;
  xt_tensor *produced = Scope.calloc(limit, sizeof(xt_tensor));
  int total;
  _check(xt_jit_forward(m.native, handles, count, produced, limit, &total),
         "jit forward");
  List results = %();
  for (int i = 0; i < total; i++) {
    Tensor value = _wrap(produced[i], "jit forward");
    results = results.append(%($value));
  }
  return results;
}

void JitModule.train(JitModule m) {
  _check(xt_jit_train(m.native, 1), "jit train");
}

void JitModule.eval(JitModule m) {
  _check(xt_jit_train(m.native, 0), "jit eval");
}

xt_jit_module JitModule.native(JitModule m) => m.native;

JitModule JitModule.free(JitModule m) {
  _jit_drop(m);
  return NULL;
}

Var Tensor.var(Tensor t) => Var.new(<torch--ten>, t);
Tensor Var.tensor(Var value) => (Tensor) value.pointer();

Var Module.var(Module m) => Var.new(<torch--mod>, m);
Module Var.module(Var value) => (Module) value.pointer();

Var Optimizer.var(Optimizer o) => Var.new(<torch--opt>, o);
Optimizer Var.optimizer(Var value) => (Optimizer) value.pointer();

Var Scheduler.var(Scheduler s) => Var.new(<torch--sch>, s);
Scheduler Var.scheduler(Var value) => (Scheduler) value.pointer();

Var JitModule.var(JitModule m) => Var.new(<torch--jit>, m);
JitModule Var.jit_module(Var value) => (JitModule) value.pointer();

protocol Torch(Tensor);
protocol Var(Tensor);
protocol Var(Module);
protocol Var(Optimizer);
protocol Var(Scheduler);
protocol Var(JitModule);

/* Lisp calls allocate in the existing session Scope. Releasing a native
   handle early leaves its wrapper until session destruction. */
#pragma private

static Tensor _lisp_tensor_arg(Var value) {
  if (value is not Tensor)
    raise %(bad-types (library "torch") (operation "tensor argument"));
  return value.tensor();
}

static Module _lisp_module_arg(Var value) {
  if (value is not Module)
    raise %(bad-types (library "torch") (operation "module argument"));
  return value.module();
}

static Optimizer _lisp_optimizer_arg(Var value) {
  if (value is not Optimizer)
    raise %(bad-types (library "torch") (operation "optimizer argument"));
  return value.optimizer();
}

$lisp.binding(torch_lisp, "torch-tensor")
static Var _lisp_tensor(List values, List shape, int dtype) =>
  Tensor.of(values, shape, dtype);

$lisp.binding(torch_lisp, "torch-linear")
static Var _lisp_linear(int inputs, int outputs) =>
  Module.linear(inputs, outputs);

$lisp.binding(torch_lisp, "torch-forward")
static Var _lisp_forward(Var model, Var input) {
  Module owner = _lisp_module_arg(model);
  Tensor tensor = _lisp_tensor_arg(input);
  return owner.forward(tensor);
}

$lisp.binding(torch_lisp, "torch-sgd")
static Var _lisp_sgd(Var model, double rate) =>
  Optimizer.sgd(_lisp_module_arg(model), rate);

$lisp.binding(torch_lisp, "torch-adam")
static Var _lisp_adam(Var model, double rate) =>
  Optimizer.adam(_lisp_module_arg(model), rate);

$lisp.binding(torch_lisp, "torch-zero-grad")
static int _lisp_zero_grad(Var optimizer) {
  _lisp_optimizer_arg(optimizer).zero_grad();
  return 1;
}

$lisp.binding(torch_lisp, "torch-step")
static int _lisp_step(Var optimizer) {
  _lisp_optimizer_arg(optimizer).step();
  return 1;
}

$lisp.binding(torch_lisp, "torch-backward")
static int _lisp_backward(Var tensor) {
  Tensor value = _lisp_tensor_arg(tensor);
  value.backward_callbacks();
  return 1;
}

$lisp.binding(torch_lisp, "torch-mse")
static Var _lisp_mse(Var prediction, Var targets) {
  Tensor left = _lisp_tensor_arg(prediction), right = _lisp_tensor_arg(targets);
  return Tensor.mse_loss(left, right);
}

$lisp.binding(torch_lisp, "torch-add")
static Var _lisp_add(Var a, Var b) {
  Tensor left = _lisp_tensor_arg(a), right = _lisp_tensor_arg(b);
  return left + right;
}

$lisp.binding(torch_lisp, "torch-mul")
static Var _lisp_mul(Var a, Var b) {
  Tensor left = _lisp_tensor_arg(a), right = _lisp_tensor_arg(b);
  return left * right;
}

$lisp.binding(torch_lisp, "torch-matmul")
static Var _lisp_matmul(Var a, Var b) {
  Tensor left = _lisp_tensor_arg(a), right = _lisp_tensor_arg(b);
  return left @ right;
}

$lisp.binding(torch_lisp, "torch-relu")
static Var _lisp_relu(Var tensor) {
  Tensor value = _lisp_tensor_arg(tensor);
  return value.relu();
}

$lisp.binding(torch_lisp, "torch-tanh")
static Var _lisp_tanh(Var tensor) {
  Tensor value = _lisp_tensor_arg(tensor);
  return value.tanh();
}

$lisp.binding(torch_lisp, "torch-item")
static Var _lisp_item(Var tensor) {
  Tensor value = _lisp_tensor_arg(tensor);
  return value.item();
}

$lisp.binding(torch_lisp, "torch-shape")
static List _lisp_shape(Var tensor) {
  Tensor value = _lisp_tensor_arg(tensor);
  return value.shape();
}

$lisp.binding(torch_lisp, "torch-values")
static List _lisp_values(Var tensor) {
  Tensor value = _lisp_tensor_arg(tensor);
  Array values = value.to_values();
  defer values.free();
  return values.list();
}

$lisp.binding(torch_lisp, "torch-save")
static int _lisp_save(Var model, String path) {
  _lisp_module_arg(model).save(path);
  return 1;
}

$lisp.binding(torch_lisp, "torch-load")
static int _lisp_load(Var model, String path) {
  _lisp_module_arg(model).load(path);
  return 1;
}

$lisp.binding(torch_lisp, "torch-free")
static int _lisp_free(Var value) {
  if (value is Tensor) value.tensor().free();
  else if (value is Module) value.module().free();
  else if (value is Optimizer) value.optimizer().free();
  else raise %(bad-types (library "torch") (operation "torch-free"));
  return 1;
}

#pragma public

/** Installs tensor, model and optimizer operations over ordinary Lisp values.
    Results belong to the Lisp session. `torch-free` releases a native handle
    early and invalidates its aliases; the wrapper remains session-owned.
    Caller-injected values retain their original owners. */
void TorchLisp.install(Lisp lisp) {
  $lisp.install(lisp, torch_lisp);
  lisp.set_global("torch-float32", (int) XT_FLOAT32);
  lisp.set_global("torch-float64", (int) XT_FLOAT64);
  lisp.set_global("torch-int64", (int) XT_INT64);
}

/* The generated operator bindings are a second unit of this package; the
   include puts them in the public header an `import "torch"` reads. */
#include "torch-ops.x"
