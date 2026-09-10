/*  torch.x -- Tensors over libtorch with x2c lifetimes and operators.

    A Tensor owns one libtorch tensor handle. The record is allocated with a
    Scope finalizer, so an operator temporary is released with the scope
    that created it; `free` releases a handle early. A failure inside
    libtorch raises `<bad-state>` carrying the first line of its message.
*/

#include <stdint.h>
#include "torch-2.10.h"

typedef enum Torch {
  TORCH_NAMESPACE
} Torch;

typedef struct Tensor *Tensor;

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

static void _tensor_drop(void *ptr) {
  Tensor tensor = ptr;
  if (tensor.native) xt_tensor_free(tensor.native);
  tensor.native = NULL;
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

static void _check(int status, String operation) {
  if (status) _torch_failed(operation);
}

static int64_t *_shape(List sizes, int *rank) {
  int count = sizes.len();
  int64_t *shape = Scope.calloc(count ? count : 1, sizeof(int64_t));
  int index = 0;
  foreach (Var size, sizes) shape[index++] = size.integer();
  *rank = count;
  return shape;
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

#pragma public

/** Copies `values`, a List of numbers or nested Lists of rows, into a new
    tensor of `shape` and `dtype`. */
Tensor Tensor.of(List values, List shape, int dtype) {
  int rank;
  int64_t *sizes = _shape(shape, &rank), total = 1, count = 0;
  for (int i = 0; i < rank; i++) total *= sizes[i];
  double *data = Scope.calloc(total ? total : 1, sizeof(double));
  _flatten(values, data, &count, total);
  if (count != total) raise %(bad-arg (library "torch")
                              (reason "fewer values than the shape holds"));
  return _wrap(xt_from_doubles(data, sizes, rank, dtype), "of");
}

/** Wraps one number as a zero-dimensional tensor. */
Tensor Tensor.scalar(double value, int dtype) =>
  _wrap(xt_scalar(value, dtype), "scalar");

/** A float64 zero-dimensional tensor, so `2.0 * t` reads as on scalars. */
Tensor double.tensor(double value) => Tensor.scalar(value, XT_FLOAT64);

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

/** Seeds libtorch's default generator for reproducible `rand`/`randn`. */
void Torch.manual_seed(long seed) { xt_manual_seed(seed); }

/** Pins the intra-op thread pool size. */
void Torch.set_num_threads(int count) { xt_set_num_threads(count); }

int Torch.num_threads(void) => xt_get_num_threads();

/** The pinned libtorch version string. */
String Torch.version(void) => String.new(xt_version());

/* Queries */

int Tensor.rank(Tensor t) => xt_rank(t.native);

long Tensor.size(Tensor t, int dim) {
  int64_t size = xt_size(t.native, dim);
  if (size < 0) _torch_failed("size");
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

long Tensor.numel(Tensor t) => xt_numel(t.native);

int Tensor.dtype(Tensor t) => xt_dtype(t.native);

int Tensor.requires_grad(Tensor t) => xt_requires_grad(t.native);

int Tensor.is_leaf(Tensor t) => xt_is_leaf(t.native);

/** The one value of a single-element tensor as a double. */
double Tensor.item(Tensor t) {
  if (xt_numel(t.native) != 1) raise %(bad-arg (library "torch")
                                        (reason "item needs one element"));
  return xt_item(t.native);
}

/** Every element, in row-major order, as an Array of doubles. */
Array Tensor.to_values(Tensor t) {
  int64_t count = xt_numel(t.native);
  double *out = Scope.calloc(count ? count : 1, sizeof(double));
  xt_copy_out_doubles(t.native, out, count);
  Array values = %[];
  for (int64_t i = 0; i < count; i++) values.push(out[i]);
  return values;
}

/** libtorch's own printed form. */
String Tensor.str(Tensor t) => String.new(xt_str(t.native));

/** The raw handle, for the C ABI in torch-2.10.h. */
xt_tensor Tensor.native(Tensor t) => t.native;

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
Tensor Tensor.sum_dim(Tensor a, int dim, int keepdim) =>
  _wrap(xt_sum_dim(a.native, dim, keepdim), "sum_dim");
Tensor Tensor.mean_dim(Tensor a, int dim, int keepdim) =>
  _wrap(xt_mean_dim(a.native, dim, keepdim), "mean_dim");
Tensor Tensor.mse_loss(Tensor input, Tensor target) =>
  _wrap(xt_mse_loss(input.native, target.native), "mse_loss");

int Tensor.allclose(Tensor a, Tensor b, double rtol, double atol) {
  int result = xt_allclose(a.native, b.native, rtol, atol);
  if (result < 0) _torch_failed("allclose");
  return result;
}

int Tensor.equal(Tensor a, Tensor b) {
  int result = xt_equal(a.native, b.native);
  if (result < 0) _torch_failed("equal");
  return result;
}

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
/** `t[index]` selects along the first dimension, as in PyTorch. */
Tensor Tensor.getindex(Tensor a, long index) => a.select(0, index);
Tensor Tensor.slice(Tensor a, int dim, long start, long end, long step) =>
  _wrap(xt_slice(a.native, dim, start, end, step), "slice");
Tensor Tensor.index_select(Tensor a, int dim, Tensor indexes) =>
  _wrap(xt_index_select(a.native, dim, indexes.native), "index_select");
Tensor Tensor.to_dtype(Tensor a, int dtype) =>
  _wrap(xt_to_dtype(a.native, dtype), "to_dtype");
Tensor Tensor.clone(Tensor a) => _wrap(xt_clone(a.native), "clone");
Tensor Tensor.contiguous(Tensor a) =>
  _wrap(xt_contiguous(a.native), "contiguous");

/* Autograd */

/** Marks `a` as a leaf that accumulates a gradient and returns it. */
Tensor Tensor.requires_grad_(Tensor a, int on) =>
  _wrap(xt_requires_grad_(a.native, on), "requires_grad_");
Tensor Tensor.detach(Tensor a) => _wrap(xt_detach(a.native), "detach");
void Tensor.backward(Tensor a) { _check(xt_backward(a.native), "backward"); }
/** The accumulated gradient; raises when none has been computed. */
Tensor Tensor.grad(Tensor a) => _wrap(xt_grad(a.native), "grad");
void Tensor.zero_grad(Tensor a) { _check(xt_zero_grad(a.native), "zero_grad"); }
/** `a += alpha * b` in place, the update step of gradient descent. */
Tensor Tensor.add_(Tensor a, Tensor b, double alpha) {
  _check(xt_add_(a.native, b.native, alpha), "add_");
  return a;
}

/** Disables gradient recording until the matching `Torch.enable_grad`. */
void Torch.no_grad(void) { xt_no_grad_push(); }
void Torch.enable_grad(void) { xt_no_grad_pop(); }
int Torch.grad_enabled(void) => xt_grad_enabled();

/** Releases the libtorch handle now; the record's finalizer then does
    nothing. Returns NULL for the adjacent-defer form. */
Tensor Tensor.free(Tensor a) {
  _tensor_drop(a);
  return NULL;
}

Var Tensor.var(Tensor t) => Var.new(<torch--ten>, t);
Tensor Var.tensor(Var value) => (Tensor) value.pointer();

protocol Torch(Tensor);
protocol Var(Tensor);
