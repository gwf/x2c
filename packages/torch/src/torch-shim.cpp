/*  torch-shim.cpp -- the C ABI over libtorch 2.10; see torch-2.10.h. */

#include <torch/torch.h>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>
#include "torch-2.10.h"

struct xt_tensor_s { at::Tensor t; };

static_assert((int) at::kFloat == XT_FLOAT32, "ScalarType values moved");
static_assert((int) at::kDouble == XT_FLOAT64, "ScalarType values moved");
static_assert((int) at::kLong == XT_INT64, "ScalarType values moved");
static_assert((int) at::kBool == XT_BOOL, "ScalarType values moved");

static thread_local std::string error_full, error_line, scratch;
static thread_local std::vector<torch::NoGradGuard *> no_grad_guards;

static void note_error(const char *what) {
  error_full = what;
  error_line = error_full.substr(0, error_full.find('\n'));
}

#define TRY(fail, ...) \
  try { __VA_ARGS__ } \
  catch (const std::exception &e) { note_error(e.what()); return fail; }

static xt_tensor wrap(at::Tensor t) { return new xt_tensor_s{std::move(t)}; }
static at::IntArrayRef dims(const int64_t *shape, int rank) {
  return at::IntArrayRef(shape, rank);
}
static at::TensorOptions options(int dtype) {
  return at::TensorOptions().dtype(static_cast<at::ScalarType>(dtype));
}

extern "C" {

const char *xt_last_error(void) { return error_line.c_str(); }
const char *xt_last_error_full(void) { return error_full.c_str(); }
const char *xt_version(void) { return TORCH_VERSION; }
void xt_manual_seed(int64_t seed) { torch::manual_seed(seed); }
void xt_set_num_threads(int count) { at::set_num_threads(count); }
int xt_get_num_threads(void) { return at::get_num_threads(); }

xt_tensor xt_from_doubles(const double *data, const int64_t *shape, int rank,
                          int dtype) {
  TRY(nullptr,
    auto t = torch::from_blob((void *) data, dims(shape, rank), at::kDouble);
    return wrap(t.to(static_cast<at::ScalarType>(dtype)).clone());)
}
xt_tensor xt_scalar(double value, int dtype) {
  TRY(nullptr, return wrap(torch::scalar_tensor(value, options(dtype)));)
}
xt_tensor xt_zeros(const int64_t *shape, int rank, int dtype) {
  TRY(nullptr, return wrap(torch::zeros(dims(shape, rank), options(dtype)));)
}
xt_tensor xt_ones(const int64_t *shape, int rank, int dtype) {
  TRY(nullptr, return wrap(torch::ones(dims(shape, rank), options(dtype)));)
}
xt_tensor xt_full(const int64_t *shape, int rank, double value, int dtype) {
  TRY(nullptr,
    return wrap(torch::full(dims(shape, rank), value, options(dtype)));)
}
xt_tensor xt_rand(const int64_t *shape, int rank, int dtype) {
  TRY(nullptr, return wrap(torch::rand(dims(shape, rank), options(dtype)));)
}
xt_tensor xt_randn(const int64_t *shape, int rank, int dtype) {
  TRY(nullptr, return wrap(torch::randn(dims(shape, rank), options(dtype)));)
}
xt_tensor xt_arange(double start, double end, double step, int dtype) {
  TRY(nullptr, return wrap(torch::arange(start, end, step, options(dtype)));)
}

int xt_rank(xt_tensor a) { return (int) a->t.dim(); }
int64_t xt_size(xt_tensor a, int dim) { TRY(-1, return a->t.size(dim);) }
int64_t xt_numel(xt_tensor a) { return a->t.numel(); }
int xt_dtype(xt_tensor a) { return (int) a->t.scalar_type(); }
int xt_requires_grad(xt_tensor a) { return a->t.requires_grad(); }
int xt_is_leaf(xt_tensor a) { return a->t.is_leaf(); }
double xt_item(xt_tensor a) { TRY(0.0, return a->t.item<double>();) }
void xt_copy_out_doubles(xt_tensor a, double *out, int64_t count) {
  auto c = a->t.detach().contiguous().to(at::kDouble);
  int64_t n = std::min<int64_t>(count, c.numel());
  std::memcpy(out, c.data_ptr<double>(), (size_t) n * sizeof(double));
}
const char *xt_str(xt_tensor a) {
  std::ostringstream out;
  out << a->t;
  scratch = out.str();
  return scratch.c_str();
}

#define BINARY(name, expr) \
  xt_tensor name(xt_tensor a, xt_tensor b) { TRY(nullptr, return wrap(expr);) }
#define UNARY(name, expr) \
  xt_tensor name(xt_tensor a) { TRY(nullptr, return wrap(expr);) }

BINARY(xt_add, a->t + b->t)
BINARY(xt_sub, a->t - b->t)
BINARY(xt_mul, a->t * b->t)
BINARY(xt_div, a->t / b->t)
BINARY(xt_matmul, a->t.matmul(b->t))
BINARY(xt_mse_loss, torch::mse_loss(a->t, b->t))
xt_tensor xt_pow(xt_tensor a, double e) { TRY(nullptr, return wrap(a->t.pow(e));) }
UNARY(xt_neg, -a->t)
UNARY(xt_abs, a->t.abs())
UNARY(xt_exp, a->t.exp())
UNARY(xt_log, a->t.log())
UNARY(xt_sqrt, a->t.sqrt())
UNARY(xt_tanh, a->t.tanh())
UNARY(xt_sigmoid, a->t.sigmoid())
UNARY(xt_relu, a->t.relu())
UNARY(xt_sum, a->t.sum())
UNARY(xt_mean, a->t.mean())
UNARY(xt_clone, a->t.clone())
UNARY(xt_contiguous, a->t.contiguous())
UNARY(xt_detach, a->t.detach())
xt_tensor xt_sum_dim(xt_tensor a, int dim, int keepdim) {
  TRY(nullptr, return wrap(a->t.sum(dim, keepdim != 0));)
}
xt_tensor xt_mean_dim(xt_tensor a, int dim, int keepdim) {
  TRY(nullptr, return wrap(a->t.mean(dim, keepdim != 0));)
}
int xt_allclose(xt_tensor a, xt_tensor b, double rtol, double atol) {
  TRY(-1, return a->t.allclose(b->t, rtol, atol) ? 1 : 0;)
}
int xt_equal(xt_tensor a, xt_tensor b) {
  TRY(-1, return a->t.equal(b->t) ? 1 : 0;)
}

xt_tensor xt_reshape(xt_tensor a, const int64_t *shape, int rank) {
  TRY(nullptr, return wrap(a->t.reshape(dims(shape, rank)));)
}
xt_tensor xt_transpose(xt_tensor a, int d0, int d1) {
  TRY(nullptr, return wrap(a->t.transpose(d0, d1));)
}
xt_tensor xt_squeeze(xt_tensor a, int dim) {
  TRY(nullptr, return wrap(a->t.squeeze(dim));)
}
xt_tensor xt_unsqueeze(xt_tensor a, int dim) {
  TRY(nullptr, return wrap(a->t.unsqueeze(dim));)
}
xt_tensor xt_select(xt_tensor a, int dim, int64_t index) {
  TRY(nullptr, return wrap(a->t.select(dim, index));)
}
xt_tensor xt_slice(xt_tensor a, int dim, int64_t start, int64_t end,
                   int64_t step) {
  TRY(nullptr, return wrap(a->t.slice(dim, start, end, step));)
}
xt_tensor xt_index_select(xt_tensor a, int dim, xt_tensor indexes) {
  TRY(nullptr, return wrap(a->t.index_select(dim, indexes->t));)
}
xt_tensor xt_to_dtype(xt_tensor a, int dtype) {
  TRY(nullptr, return wrap(a->t.to(static_cast<at::ScalarType>(dtype)));)
}

xt_tensor xt_requires_grad_(xt_tensor a, int on) {
  TRY(nullptr, a->t.set_requires_grad(on != 0); return wrap(a->t);)
}
int xt_backward(xt_tensor a) { TRY(-1, a->t.backward(); return 0;) }
xt_tensor xt_grad(xt_tensor a) {
  TRY(nullptr,
    if (!a->t.grad().defined()) {
      note_error("tensor has no gradient");
      return nullptr;
    }
    return wrap(a->t.grad());)
}
int xt_zero_grad(xt_tensor a) {
  TRY(-1, if (a->t.grad().defined()) a->t.mutable_grad().zero_(); return 0;)
}
int xt_add_(xt_tensor a, xt_tensor b, double alpha) {
  TRY(-1, a->t.add_(b->t, alpha); return 0;)
}
void xt_no_grad_push(void) { no_grad_guards.push_back(new torch::NoGradGuard); }
void xt_no_grad_pop(void) {
  if (no_grad_guards.empty()) return;
  delete no_grad_guards.back();
  no_grad_guards.pop_back();
}
int xt_grad_enabled(void) { return torch::GradMode::is_enabled(); }

void xt_tensor_free(xt_tensor a) { delete a; }

}
