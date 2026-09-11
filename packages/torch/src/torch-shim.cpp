/*  torch-shim.cpp -- the C ABI over libtorch 2.10; see torch-2.10.h.

    libtorch reports every failure by throwing, so each entry point below
    is wrapped in TRY. Nothing here lets a C++ exception reach C.
*/

#include <torch/torch.h>
#include <torch/script.h>
#include <torch/mps.h>
#include <torch/csrc/autograd/custom_function.h>
#include <c10/core/AutogradState.h>
#include <thread>
#include <cmath>
#include <unordered_set>
#include <torch/csrc/jit/serialization/pickle.h>
#include <torch/optim/schedulers/reduce_on_plateau_scheduler.h>
#include <torch/optim/schedulers/step_lr.h>
#include <ATen/core/ivalue.h>
#include <cstring>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>
#include "torch-2.10.h"
#include "xt-handles.h"

struct xt_tensor_s { at::Tensor t; };

static_assert((int) at::kFloat == XT_FLOAT32, "ScalarType values moved");
static_assert((int) at::kDouble == XT_FLOAT64, "ScalarType values moved");
static_assert((int) at::kLong == XT_INT64, "ScalarType values moved");
static_assert((int) at::kBool == XT_BOOL, "ScalarType values moved");

static thread_local std::string error_full, error_line, scratch;
static thread_local bool custom_invocation = false, custom_callback = false;
static thread_local std::vector<torch::NoGradGuard *> no_grad_guards;
static thread_local std::vector<c10::InferenceMode *> inference_guards;

static void note_error(const std::string &what) {
  error_full = what;
  error_line = error_full.substr(0, error_full.find('\n'));
}

/* The generated bindings in generated/ report through this same error. */
extern "C" void xt_note_error(const char *what) { note_error(what); }

#define TRY(fail, ...) \
  try { __VA_ARGS__ } \
  catch (const std::exception &e) { note_error(e.what()); return fail; }

/* A void entry that still has to swallow anything thrown under it. */
#define TRY_VOID(...) \
  try { __VA_ARGS__ } \
  catch (const std::exception &e) { note_error(e.what()); }

static xt_tensor wrap(at::Tensor t) {
  XT_HANDLE_NEW(XT_HANDLE_TENSOR);
  return new xt_tensor_s{std::move(t)};
}
static at::IntArrayRef dims(const int64_t *shape, int rank) {
  return at::IntArrayRef(shape, rank);
}
static at::TensorOptions options(int dtype) {
  return at::TensorOptions().dtype(static_cast<at::ScalarType>(dtype));
}
static std::vector<at::Tensor> gather(xt_tensor *tensors, int count) {
  std::vector<at::Tensor> values;
  values.reserve((size_t) (count > 0 ? count : 0));
  for (int i = 0; i < count; i++) values.push_back(tensors[i]->t);
  return values;
}

extern "C" {

const char *xt_last_error(void) { return error_line.c_str(); }
const char *xt_last_error_full(void) { return error_full.c_str(); }
const char *xt_version(void) { return TORCH_VERSION; }
int xt_mps_available(int *out) {
  TRY(-1, *out = torch::mps::is_available();) return 0;
}
int xt_mps_synchronize(void) {
  TRY(-1, torch::mps::synchronize();) return 0;
}
const char *xt_device(xt_tensor a) {
  TRY(nullptr, scratch = a->t.device().str(); return scratch.c_str();)
}
int xt_manual_seed(int64_t seed) {
  TRY(-1, torch::manual_seed(seed);) return 0;
}
int xt_set_num_threads(int count) {
  TRY(-1, at::set_num_threads(count);) return 0;
}
int xt_get_num_threads(int *out) {
  TRY(-1, *out = at::get_num_threads();) return 0;
}
int xt_set_num_interop_threads(int count) {
  TRY(-1, at::set_num_interop_threads(count);) return 0;
}
int xt_get_num_interop_threads(int *out) {
  TRY(-1, *out = at::get_num_interop_threads();) return 0;
}

/* Creation */

xt_tensor xt_from_doubles(const double *data, const int64_t *shape, int rank,
                          int dtype) {
  TRY(nullptr,
    auto t = torch::from_blob((void *) data, dims(shape, rank), at::kDouble);
    return wrap(t.to(static_cast<at::ScalarType>(dtype)).clone());)
}
xt_tensor xt_from_int64s(const int64_t *data, const int64_t *shape, int rank,
                         int dtype) {
  TRY(nullptr,
    auto t = torch::from_blob((void *) data, dims(shape, rank), at::kLong);
    return wrap(t.to(static_cast<at::ScalarType>(dtype)).clone());)
}
xt_tensor xt_scalar(double value, int dtype) {
  TRY(nullptr, return wrap(torch::scalar_tensor(value, options(dtype)));)
}
xt_tensor xt_scalar_int64(int64_t value, int dtype) {
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
xt_tensor xt_randperm(int64_t n) {
  TRY(nullptr, return wrap(torch::randperm(n, options(XT_INT64)));)
}

/* Queries */

int xt_rank(xt_tensor a, int *out) {
  TRY(-1, *out = (int) a->t.dim();) return 0;
}
int xt_size(xt_tensor a, int dim, int64_t *out) {
  TRY(-1, *out = a->t.size(dim);) return 0;
}
int xt_numel(xt_tensor a, int64_t *out) {
  TRY(-1, *out = a->t.numel();) return 0;
}
int xt_dtype(xt_tensor a, int *out) {
  TRY(-1, *out = (int) a->t.scalar_type();) return 0;
}
int xt_requires_grad(xt_tensor a, int *out) {
  TRY(-1, *out = a->t.requires_grad() ? 1 : 0;) return 0;
}
int xt_is_leaf(xt_tensor a, int *out) {
  TRY(-1, *out = a->t.is_leaf() ? 1 : 0;) return 0;
}
int xt_item_double(xt_tensor a, double *out) {
  TRY(-1, *out = a->t.item<double>();) return 0;
}
int xt_item_int64(xt_tensor a, int64_t *out) {
  TRY(-1, *out = a->t.item<int64_t>();) return 0;
}
int xt_copy_out_doubles(xt_tensor a, double *out, int64_t count) {
  TRY(-1,
    auto c = a->t.detach().to(at::kCPU).contiguous().to(at::kDouble);
    int64_t n = std::min<int64_t>(count, c.numel());
    std::memcpy(out, c.data_ptr<double>(), (size_t) n * sizeof(double));)
  return 0;
}
int xt_copy_out_int64s(xt_tensor a, int64_t *out, int64_t count) {
  TRY(-1,
    auto c = a->t.detach().to(at::kCPU).contiguous().to(at::kLong);
    int64_t n = std::min<int64_t>(count, c.numel());
    std::memcpy(out, c.data_ptr<int64_t>(), (size_t) n * sizeof(int64_t));)
  return 0;
}
const char *xt_str(xt_tensor a) {
  TRY(nullptr,
    std::ostringstream out;
    out << a->t;
    scratch = out.str();
    return scratch.c_str();)
}

/* Arithmetic, reductions, losses, and comparison */

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
BINARY(xt_cross_entropy, torch::nn::functional::cross_entropy(a->t, b->t))
BINARY(xt_nll_loss, torch::nll_loss(a->t, b->t))
BINARY(xt_bce_with_logits, torch::binary_cross_entropy_with_logits(a->t, b->t))
BINARY(xt_eq, a->t.eq(b->t))
BINARY(xt_gt, a->t.gt(b->t))
BINARY(xt_lt, a->t.lt(b->t))
BINARY(xt_masked_select, a->t.masked_select(b->t))
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
UNARY(xt_max_all, a->t.max())
UNARY(xt_min_all, a->t.min())
UNARY(xt_to_bool, a->t.to(at::kBool))
UNARY(xt_clone, a->t.clone())
UNARY(xt_contiguous, a->t.contiguous())
UNARY(xt_detach, a->t.detach())

xt_tensor xt_pow(xt_tensor a, double e) {
  TRY(nullptr, return wrap(a->t.pow(e));)
}
xt_tensor xt_sum_dim(xt_tensor a, int dim, int keepdim) {
  TRY(nullptr, return wrap(a->t.sum(dim, keepdim != 0));)
}
xt_tensor xt_mean_dim(xt_tensor a, int dim, int keepdim) {
  TRY(nullptr, return wrap(a->t.mean(dim, keepdim != 0));)
}
xt_tensor xt_argmax(xt_tensor a, int dim, int keepdim) {
  TRY(nullptr, return wrap(a->t.argmax(dim, keepdim != 0));)
}
xt_tensor xt_softmax(xt_tensor a, int dim) {
  TRY(nullptr, return wrap(a->t.softmax(dim));)
}
xt_tensor xt_log_softmax(xt_tensor a, int dim) {
  TRY(nullptr, return wrap(a->t.log_softmax(dim));)
}
xt_tensor xt_where(xt_tensor condition, xt_tensor a, xt_tensor b) {
  TRY(nullptr, return wrap(torch::where(condition->t, a->t, b->t));)
}
int xt_allclose(xt_tensor a, xt_tensor b, double rtol, double atol, int *out) {
  TRY(-1, *out = a->t.allclose(b->t, rtol, atol) ? 1 : 0;) return 0;
}
int xt_equal(xt_tensor a, xt_tensor b, int *out) {
  TRY(-1, *out = a->t.equal(b->t) ? 1 : 0;) return 0;
}

/* Shape and indexing */

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
xt_tensor xt_narrow(xt_tensor a, int dim, int64_t start, int64_t length) {
  TRY(nullptr, return wrap(a->t.narrow(dim, start, length));)
}
xt_tensor xt_flatten(xt_tensor a, int start, int end) {
  TRY(nullptr, return wrap(a->t.flatten(start, end));)
}
xt_tensor xt_index_select(xt_tensor a, int dim, xt_tensor indexes) {
  TRY(nullptr, return wrap(a->t.index_select(dim, indexes->t));)
}
xt_tensor xt_cat(xt_tensor *tensors, int count, int dim) {
  TRY(nullptr, return wrap(torch::cat(gather(tensors, count), dim));)
}
xt_tensor xt_stack(xt_tensor *tensors, int count, int dim) {
  TRY(nullptr, return wrap(torch::stack(gather(tensors, count), dim));)
}
xt_tensor xt_to_dtype(xt_tensor a, int dtype) {
  TRY(nullptr, return wrap(a->t.to(static_cast<at::ScalarType>(dtype)));)
}

/* Autograd */

xt_tensor xt_requires_grad_(xt_tensor a, int on) {
  TRY(nullptr, a->t.set_requires_grad(on != 0); return wrap(a->t);)
}
int xt_backward(xt_tensor a) {
  TRY(-1,
    TORCH_CHECK(!custom_callback, "backward inside an x2c autograd callback");
    a->t.backward();)
  return 0;
}
xt_tensor xt_grad(xt_tensor a) {
  TRY(nullptr,
    if (!a->t.grad().defined()) {
      note_error("tensor has no gradient");
      return nullptr;
    }
    return wrap(a->t.grad());)
}
int xt_zero_grad(xt_tensor a) {
  TRY(-1, if (a->t.grad().defined()) a->t.mutable_grad().zero_();) return 0;
}
int xt_add_(xt_tensor a, xt_tensor b, double alpha) {
  TRY(-1, a->t.add_(b->t, alpha);) return 0;
}
int xt_copy_(xt_tensor dst, xt_tensor src) {
  TRY(-1, torch::NoGradGuard hold; dst->t.copy_(src->t);) return 0;
}
int xt_no_grad_push(void) {
  TRY(-1, no_grad_guards.push_back(new torch::NoGradGuard);) return 0;
}
int xt_no_grad_pop(void) {
  if (no_grad_guards.empty()) {
    note_error("no_grad stack is empty");
    return -1;
  }
  delete no_grad_guards.back();
  no_grad_guards.pop_back();
  return 0;
}
int xt_grad_enabled(int *out) {
  TRY(-1, *out = torch::GradMode::is_enabled() ? 1 : 0;) return 0;
}
int xt_inference_mode_push(void) {
  TRY(-1, inference_guards.push_back(new c10::InferenceMode);) return 0;
}
int xt_inference_mode_pop(void) {
  if (inference_guards.empty()) {
    note_error("inference mode stack is empty");
    return -1;
  }
  delete inference_guards.back();
  inference_guards.pop_back();
  return 0;
}

void xt_tensor_free(xt_tensor a) {
  if (a) XT_HANDLE_DROP(XT_HANDLE_TENSOR);
  TRY_VOID(delete a;)
}

/* Modules.

   ComposedModule is a torch::nn::Module with no forward of its own. Its
   children are registered by name from x2c, so parameters(), zero_grad,
   and serialization see a real module tree while the forward stays in
   x2c. Every handle holds a shared_ptr, so a child handle and its parent
   own the same object.
*/
namespace {
struct ComposedModule : torch::nn::Module {
  ComposedModule() = default;
};

/* SequentialModule forwards its registered children in registration
   order. libtorch's own Sequential holds type-erased AnyModules built
   from a concrete forward signature, which a shared_ptr<Module> arriving
   through a C ABI cannot supply; registration order in the module tree
   carries the same information. */
struct SequentialModule : torch::nn::Module {
  SequentialModule() = default;
};
}

} // extern "C"

struct xt_autograd_context_s {
  torch::autograd::AutogradContext *native;
  std::vector<at::Tensor> *outputs;
  bool forward;
};
struct CustomBinding : torch::CustomClassHolder {
  xt_autograd_callback callback;
  void *forward, *backward;
  std::thread::id thread;
  CustomBinding(xt_autograd_callback callback, void *forward, void *backward)
    : callback(callback), forward(forward), backward(backward),
      thread(std::this_thread::get_id()) {}
};
struct CustomInvocation {
  bool previous, multithreading;
  CustomInvocation() : previous(custom_invocation), multithreading(
      c10::AutogradState::get_tls_state().get_multithreading_enabled()) {
    TORCH_CHECK(!custom_callback, "backward inside an x2c autograd callback");
    custom_invocation = true;
    c10::AutogradState::get_tls_state().set_multithreading_enabled(false);
  }
  ~CustomInvocation() {
    c10::AutogradState::get_tls_state()
      .set_multithreading_enabled(multithreading);
    custom_invocation = previous;
  }
};
struct CustomCallbackGuard {
  bool previous = custom_callback;
  CustomCallbackGuard() { custom_callback = true; }
  ~CustomCallbackGuard() { custom_callback = previous; }
};
static std::vector<at::Tensor> custom_call(
    CustomBinding &binding, torch::autograd::AutogradContext *context,
    at::TensorList inputs, int outputs, bool forward) {
  TORCH_CHECK(binding.thread == std::this_thread::get_id(),
              "x2c autograd callback must run on its creating thread");
  TORCH_CHECK(custom_invocation,
              "use backward_callbacks for an x2c autograd graph");
  std::vector<xt_tensor_s> storage;
  storage.reserve(inputs.size());
  for (auto &tensor : inputs) storage.push_back({tensor});
  std::vector<xt_tensor> handles;
  for (auto &tensor : storage) handles.push_back(&tensor);
  std::vector<at::Tensor> result(outputs);
  xt_autograd_context_s bridge{context, &result, forward};
  std::vector<int64_t> versions;
  if (forward) for (auto &input : inputs)
    versions.push_back(input.is_inference() ? -1 : input._version());
  int status;
  {
    CustomCallbackGuard guard;
    status = binding.callback(forward ? binding.forward : binding.backward,
                              &bridge, handles.data(), (int) handles.size(),
                              forward ? 1 : 0, outputs);
  }
  if (forward) for (size_t i = 0; i < inputs.size(); i++)
    TORCH_CHECK(versions[i] < 0 || inputs[i]._version() == versions[i],
                "custom forward may not mutate its inputs in place");
  TORCH_CHECK(status == 0, "x2c autograd callback raised an Error");
  if (forward) TORCH_CHECK(result[0].defined(), "custom forward returned Null");
  return result;
}
struct CustomFunction : torch::autograd::Function<CustomFunction> {
  static at::Tensor forward(torch::autograd::AutogradContext *context,
      c10::intrusive_ptr<CustomBinding> binding, at::TensorList inputs) {
    context->saved_data["binding"] = c10::IValue::make_capsule(binding);
    context->saved_data["count"] = (int64_t) inputs.size();
    return custom_call(*binding, context, inputs, 1, true)[0];
  }
  static torch::autograd::variable_list backward(
      torch::autograd::AutogradContext *context,
      torch::autograd::variable_list gradients) {
    auto binding = context->saved_data.at("binding").toCapsule();
    auto result = custom_call(*static_cast<CustomBinding *>(binding.get()),
      context, gradients, (int) context->saved_data.at("count").toInt(), false);
    result.insert(result.begin(), at::Tensor()); // non-tensor binding argument
    return result;
  }
};

extern "C" {
xt_tensor xt_tensor_alias(xt_tensor tensor) {
  TRY(nullptr, return wrap(tensor->t);)
}
xt_tensor xt_custom(xt_autograd_callback callback, void *forward, void *backward,
                    xt_tensor *inputs, int count) {
  TRY(nullptr,
    TORCH_CHECK(!custom_callback, "nested x2c autograd callbacks unsupported");
    CustomInvocation invocation;
    auto binding = c10::make_intrusive<CustomBinding>(callback, forward, backward);
    auto tensors = gather(inputs, count);
    return wrap(CustomFunction::apply(binding, at::TensorList(tensors)));)
}
int xt_backward_callbacks(xt_tensor output) {
  TRY(-1, CustomInvocation invocation; output->t.backward();)
  return 0;
}
int xt_custom_output(xt_autograd_context context, int index, xt_tensor tensor) {
  TRY(-1,
    TORCH_CHECK(index >= 0 && (size_t) index < context->outputs->size(),
                "wrong number of custom autograd outputs");
    (*context->outputs)[index] = tensor ? tensor->t : at::Tensor();)
  return 0;
}
int xt_custom_save(xt_autograd_context context, xt_tensor *tensors, int count) {
  TRY(-1,
    TORCH_CHECK(context->forward, "save_for_backward belongs in forward");
    context->native->save_for_backward(gather(tensors, count));)
  return 0;
}
int xt_custom_saved_count(xt_autograd_context context, int *count) {
  TRY(-1, *count = (int) context->native->get_saved_variables().size();)
  return 0;
}
xt_tensor xt_custom_saved(xt_autograd_context context, int index) {
  TRY(nullptr,
    auto values = context->native->get_saved_variables();
    TORCH_CHECK(index >= 0 && (size_t) index < values.size(),
                "saved tensor index out of range");
    return wrap(values[index]);)
}
int xt_custom_needs_grad(xt_autograd_context context, int index, int *out) {
  TRY(-1,
    TORCH_CHECK(index >= 0 && index < context->native->saved_data.at("count")
      .toInt(), "input gradient index out of range");
    *out = context->native->needs_input_grad((size_t) index);)
  return 0;
}

struct xt_module_s {
  std::shared_ptr<torch::nn::Module> m;
  std::string scratch;
};

static xt_module wrap_module(std::shared_ptr<torch::nn::Module> m) {
  XT_HANDLE_NEW(XT_HANDLE_MODULE);
  return new xt_module_s{std::move(m), std::string()};
}

xt_module xt_linear_new(int64_t in_features, int64_t out_features, int bias) {
  TRY(nullptr,
    auto shape = torch::nn::LinearOptions(in_features, out_features)
      .bias(bias != 0);
    return wrap_module(std::make_shared<torch::nn::LinearImpl>(shape));)
}
xt_module xt_composed_new(void) {
  TRY(nullptr, return wrap_module(std::make_shared<ComposedModule>());)
}
xt_module xt_sequential_new(void) {
  TRY(nullptr, return wrap_module(std::make_shared<SequentialModule>());)
}
xt_module xt_conv1d_new(int64_t in_channels, int64_t out_channels,
                        int64_t kernel, int64_t stride, int64_t padding,
                        int64_t dilation, int64_t groups, int bias) {
  TRY(nullptr,
    auto shape = torch::nn::Conv1dOptions(in_channels, out_channels, kernel)
      .stride(stride).padding(padding).dilation(dilation).groups(groups)
      .bias(bias != 0);
    return wrap_module(std::make_shared<torch::nn::Conv1dImpl>(shape));)
}
xt_module xt_conv2d_new(int64_t in_channels, int64_t out_channels,
                        int64_t kernel, int64_t stride, int64_t padding,
                        int64_t dilation, int64_t groups, int bias) {
  TRY(nullptr,
    auto shape = torch::nn::Conv2dOptions(in_channels, out_channels, kernel)
      .stride(stride).padding(padding).dilation(dilation).groups(groups)
      .bias(bias != 0);
    return wrap_module(std::make_shared<torch::nn::Conv2dImpl>(shape));)
}
xt_module xt_batch_norm1d_new(int64_t features, double eps, double momentum,
                              int affine, int track_running_stats) {
  TRY(nullptr,
    auto shape = torch::nn::BatchNorm1dOptions(features).eps(eps)
      .momentum(momentum).affine(affine != 0)
      .track_running_stats(track_running_stats != 0);
    return wrap_module(std::make_shared<torch::nn::BatchNorm1dImpl>(shape));)
}
xt_module xt_batch_norm2d_new(int64_t features, double eps, double momentum,
                              int affine, int track_running_stats) {
  TRY(nullptr,
    auto shape = torch::nn::BatchNorm2dOptions(features).eps(eps)
      .momentum(momentum).affine(affine != 0)
      .track_running_stats(track_running_stats != 0);
    return wrap_module(std::make_shared<torch::nn::BatchNorm2dImpl>(shape));)
}
xt_module xt_layer_norm_new(const int64_t *shape, int rank, double eps,
                            int affine) {
  TRY(nullptr,
    std::vector<int64_t> normalized(shape, shape + (rank > 0 ? rank : 0));
    auto options = torch::nn::LayerNormOptions(normalized).eps(eps)
      .elementwise_affine(affine != 0);
    return wrap_module(std::make_shared<torch::nn::LayerNormImpl>(options));)
}
xt_module xt_dropout_new(double p) {
  TRY(nullptr,
    return wrap_module(std::make_shared<torch::nn::DropoutImpl>(
      torch::nn::DropoutOptions(p)));)
}
xt_module xt_embedding_new(int64_t num_embeddings, int64_t dim) {
  TRY(nullptr,
    return wrap_module(std::make_shared<torch::nn::EmbeddingImpl>(
      torch::nn::EmbeddingOptions(num_embeddings, dim)));)
}
xt_module xt_lstm_new(int64_t input_size, int64_t hidden_size,
                      int64_t layers, int batch_first) {
  TRY(nullptr,
    auto shape = torch::nn::LSTMOptions(input_size, hidden_size)
      .num_layers(layers).batch_first(batch_first != 0);
    return wrap_module(std::make_shared<torch::nn::LSTMImpl>(shape));)
}
xt_module xt_gru_new(int64_t input_size, int64_t hidden_size, int64_t layers,
                     int batch_first) {
  TRY(nullptr,
    auto shape = torch::nn::GRUOptions(input_size, hidden_size)
      .num_layers(layers).batch_first(batch_first != 0);
    return wrap_module(std::make_shared<torch::nn::GRUImpl>(shape));)
}
xt_module xt_max_pool2d_new(int64_t kernel, int64_t stride, int64_t padding) {
  TRY(nullptr,
    auto shape = torch::nn::MaxPool2dOptions(kernel).stride(stride)
      .padding(padding);
    return wrap_module(std::make_shared<torch::nn::MaxPool2dImpl>(shape));)
}
xt_module xt_avg_pool2d_new(int64_t kernel, int64_t stride, int64_t padding) {
  TRY(nullptr,
    auto shape = torch::nn::AvgPool2dOptions(kernel).stride(stride)
      .padding(padding);
    return wrap_module(std::make_shared<torch::nn::AvgPool2dImpl>(shape));)
}
xt_module xt_flatten_new(int64_t start_dim, int64_t end_dim) {
  TRY(nullptr,
    auto shape = torch::nn::FlattenOptions().start_dim(start_dim)
      .end_dim(end_dim);
    return wrap_module(std::make_shared<torch::nn::FlattenImpl>(shape));)
}
xt_module xt_relu_new(void) {
  TRY(nullptr, return wrap_module(std::make_shared<torch::nn::ReLUImpl>());)
}
xt_module xt_tanh_new(void) {
  TRY(nullptr, return wrap_module(std::make_shared<torch::nn::TanhImpl>());)
}
xt_module xt_sigmoid_new(void) {
  TRY(nullptr,
    return wrap_module(std::make_shared<torch::nn::SigmoidImpl>());)
}
int xt_module_register_module(xt_module parent, const char *name,
                              xt_module child) {
  TRY(-1, parent->m->register_module(name, child->m);) return 0;
}
int xt_module_register_parameter(xt_module parent, const char *name,
                                 xt_tensor value, int requires_grad) {
  TRY(-1, parent->m->register_parameter(name, value->t, requires_grad != 0);)
  return 0;
}
int xt_module_register_buffer(xt_module parent, const char *name,
                              xt_tensor value) {
  TRY(-1, parent->m->register_buffer(name, value->t);) return 0;
}
xt_module xt_module_child(xt_module parent, const char *name) {
  TRY(nullptr,
    /* named_children() returns by value, so the dict has to outlive the
       lookup. */
    auto children = parent->m->named_children();
    auto *found = children.find(name);
    if (!found) {
      note_error(std::string("no child module named ") + name);
      return nullptr;
    }
    return wrap_module(*found);)
}
/* Every native forward dispatches here. A composed root has none: its
   forward is written in x2c and never enters C++. The recurrent layers
   produce a state as well and go through xt_rnn_forward instead. */
static bool forward_native(const std::shared_ptr<torch::nn::Module> &m,
                           const at::Tensor &in, at::Tensor &out) {
  if (auto *layer = m->as<torch::nn::LinearImpl>()) {
    out = layer->forward(in);
  }
  else if (auto *layer = m->as<torch::nn::Conv1dImpl>()) {
    out = layer->forward(in);
  }
  else if (auto *layer = m->as<torch::nn::Conv2dImpl>()) {
    out = layer->forward(in);
  }
  else if (auto *layer = m->as<torch::nn::BatchNorm1dImpl>()) {
    out = layer->forward(in);
  }
  else if (auto *layer = m->as<torch::nn::BatchNorm2dImpl>()) {
    out = layer->forward(in);
  }
  else if (auto *layer = m->as<torch::nn::LayerNormImpl>()) {
    out = layer->forward(in);
  }
  else if (auto *layer = m->as<torch::nn::DropoutImpl>()) {
    out = layer->forward(in);
  }
  else if (auto *layer = m->as<torch::nn::EmbeddingImpl>()) {
    out = layer->forward(in);
  }
  else if (auto *layer = m->as<torch::nn::MaxPool2dImpl>()) {
    out = layer->forward(in);
  }
  else if (auto *layer = m->as<torch::nn::AvgPool2dImpl>()) {
    out = layer->forward(in);
  }
  else if (auto *layer = m->as<torch::nn::FlattenImpl>()) {
    out = layer->forward(in);
  }
  else if (auto *layer = m->as<torch::nn::ReLUImpl>()) {
    out = layer->forward(in);
  }
  else if (auto *layer = m->as<torch::nn::TanhImpl>()) {
    out = layer->forward(in);
  }
  else if (auto *layer = m->as<torch::nn::SigmoidImpl>()) {
    out = layer->forward(in);
  }
  else if (m->as<SequentialModule>()) {
    at::Tensor value = in;
    for (const auto &child : m->children()) {
      at::Tensor next;
      if (!forward_native(child, value, next))
        throw std::runtime_error(
          "a sequential child has no native forward");
      value = next;
    }
    out = value;
  }
  else {
    return false;
  }
  return true;
}

xt_tensor xt_module_forward(xt_module m, xt_tensor input) {
  TRY(nullptr,
    at::Tensor out;
    if (forward_native(m->m, input->t, out)) return wrap(out);
    note_error("module has no native forward; compose it in x2c");
    return nullptr;)
}
int xt_rnn_forward(xt_module m, xt_tensor input, xt_tensor *output,
                   xt_tensor *hidden, xt_tensor *cell) {
  TRY(-1,
    *output = nullptr;
    *hidden = nullptr;
    *cell = nullptr;
    if (auto *layer = m->m->as<torch::nn::LSTMImpl>()) {
      auto result = layer->forward(input->t);
      *output = wrap(std::get<0>(result));
      *hidden = wrap(std::get<0>(std::get<1>(result)));
      *cell = wrap(std::get<1>(std::get<1>(result)));
      return 0;
    }
    if (auto *layer = m->m->as<torch::nn::GRUImpl>()) {
      auto result = layer->forward(input->t);
      *output = wrap(std::get<0>(result));
      *hidden = wrap(std::get<1>(result));
      return 0;
    }
    note_error("module is not a recurrent layer");
    return -1;)
}
int xt_module_child_count(xt_module m, int64_t *out) {
  TRY(-1, *out = (int64_t) m->m->children().size();) return 0;
}
int xt_module_parameter_count(xt_module m, int64_t *out) {
  TRY(-1, *out = (int64_t) m->m->named_parameters(true).size();) return 0;
}
const char *xt_module_parameter_name(xt_module m, int64_t index) {
  TRY(nullptr,
    m->scratch = m->m->named_parameters(true)[index].key();
    return m->scratch.c_str();)
}
xt_tensor xt_module_parameter(xt_module m, int64_t index) {
  TRY(nullptr, return wrap(m->m->named_parameters(true)[index].value());)
}
int xt_module_buffer_count(xt_module m, int64_t *out) {
  TRY(-1, *out = (int64_t) m->m->named_buffers(true).size();) return 0;
}
const char *xt_module_buffer_name(xt_module m, int64_t index) {
  TRY(nullptr,
    m->scratch = m->m->named_buffers(true)[index].key();
    return m->scratch.c_str();)
}
xt_tensor xt_module_buffer(xt_module m, int64_t index) {
  TRY(nullptr, return wrap(m->m->named_buffers(true)[index].value());)
}
int xt_module_train(xt_module m, int on) {
  TRY(-1, m->m->train(on != 0);) return 0;
}
int xt_module_is_training(xt_module m, int *out) {
  TRY(-1, *out = m->m->is_training() ? 1 : 0;) return 0;
}
int xt_module_zero_grad(xt_module m) { TRY(-1, m->m->zero_grad();) return 0; }
int xt_module_to_dtype(xt_module m, int dtype) {
  TRY(-1, m->m->to(static_cast<at::ScalarType>(dtype));) return 0;
}
int xt_module_to_device(xt_module m, const char *device) {
  TRY(-1, m->m->to(at::Device(device));) return 0;
}
void xt_module_free(xt_module m) {
  if (m) XT_HANDLE_DROP(XT_HANDLE_MODULE);
  TRY_VOID(delete m;)
}

/* Optimizers */

struct xt_optim_s { std::unique_ptr<torch::optim::Optimizer> o; };

static xt_optim wrap_optim(std::unique_ptr<torch::optim::Optimizer> o) {
  XT_HANDLE_NEW(XT_HANDLE_OPTIM);
  return new xt_optim_s{std::move(o)};
}

xt_optim xt_sgd_new(xt_module m, double lr, double momentum,
                    double weight_decay, int nesterov) {
  TRY(nullptr,
    auto shape = torch::optim::SGDOptions(lr).momentum(momentum)
      .weight_decay(weight_decay).nesterov(nesterov != 0);
    return wrap_optim(std::make_unique<torch::optim::SGD>(
      m->m->parameters(true), shape));)
}
xt_optim xt_adam_new(xt_module m, double lr, double beta1, double beta2,
                     double eps, double weight_decay, int amsgrad) {
  TRY(nullptr,
    auto shape = torch::optim::AdamOptions(lr).betas({beta1, beta2})
      .eps(eps).weight_decay(weight_decay).amsgrad(amsgrad != 0);
    return wrap_optim(std::make_unique<torch::optim::Adam>(
      m->m->parameters(true), shape));)
}
xt_optim xt_adamw_new(xt_module m, double lr, double beta1, double beta2,
                      double eps, double weight_decay, int amsgrad) {
  TRY(nullptr,
    auto shape = torch::optim::AdamWOptions(lr).betas({beta1, beta2})
      .eps(eps).weight_decay(weight_decay).amsgrad(amsgrad != 0);
    return wrap_optim(std::make_unique<torch::optim::AdamW>(
      m->m->parameters(true), shape));)
}
xt_optim xt_rmsprop_new(xt_module m, double lr, double alpha, double eps,
                        double weight_decay, double momentum) {
  TRY(nullptr,
    auto shape = torch::optim::RMSpropOptions(lr).alpha(alpha).eps(eps)
      .weight_decay(weight_decay).momentum(momentum);
    return wrap_optim(std::make_unique<torch::optim::RMSprop>(
      m->m->parameters(true), shape));)
}
xt_optim xt_adagrad_new(xt_module m, double lr, double weight_decay) {
  TRY(nullptr,
    auto shape = torch::optim::AdagradOptions(lr).weight_decay(weight_decay);
    return wrap_optim(std::make_unique<torch::optim::Adagrad>(
      m->m->parameters(true), shape));)
}
xt_optim xt_optim_new_from_tensors(int kind, xt_tensor *tensors, int count,
                                   double lr) {
  TRY(nullptr,
    auto values = gather(tensors, count);
    switch (kind) {
    case XT_SGD:
      return wrap_optim(std::make_unique<torch::optim::SGD>(
        values, torch::optim::SGDOptions(lr)));
    case XT_ADAM:
      return wrap_optim(std::make_unique<torch::optim::Adam>(
        values, torch::optim::AdamOptions(lr)));
    case XT_ADAMW:
      return wrap_optim(std::make_unique<torch::optim::AdamW>(
        values, torch::optim::AdamWOptions(lr)));
    case XT_RMSPROP:
      return wrap_optim(std::make_unique<torch::optim::RMSprop>(
        values, torch::optim::RMSpropOptions(lr)));
    case XT_ADAGRAD:
      return wrap_optim(std::make_unique<torch::optim::Adagrad>(
        values, torch::optim::AdagradOptions(lr)));
    }
    note_error("unknown optimizer kind");
    return nullptr;)
}
int xt_optim_zero_grad(xt_optim o) { TRY(-1, o->o->zero_grad();) return 0; }
int xt_optim_step(xt_optim o) { TRY(-1, o->o->step();) return 0; }
int xt_optim_lr(xt_optim o, double *out) {
  TRY(-1,
    if (o->o->param_groups().empty()) {
      note_error("optimizer has no parameter group");
      return -1;
    }
    *out = o->o->param_groups()[0].options().get_lr();)
  return 0;
}
int xt_optim_set_lr(xt_optim o, double lr) {
  TRY(-1, for (auto &group : o->o->param_groups()) group.options().set_lr(lr);)
  return 0;
}
int xt_optim_save(xt_optim o, const char *path) {
  TRY(-1,
    torch::serialize::OutputArchive archive;
    o->o->save(archive);
    archive.save_to(path);)
  return 0;
}
int xt_optim_load(xt_optim o, const char *path) {
  TRY(-1,
    torch::serialize::InputArchive archive;
    archive.load_from(path);
    o->o->load(archive);)
  return 0;
}
void xt_optim_free(xt_optim o) {
  if (o) XT_HANDLE_DROP(XT_HANDLE_OPTIM);
  TRY_VOID(delete o;)
}

/* Schedulers */

struct xt_scheduler_s {
  std::unique_ptr<torch::optim::StepLR> step_lr;
  std::unique_ptr<torch::optim::ReduceLROnPlateauScheduler> plateau;
};

xt_scheduler xt_step_lr_new(xt_optim o, int step_size, double gamma) {
  TRY(nullptr,
    auto s = std::make_unique<torch::optim::StepLR>(
      *o->o, (unsigned) step_size, gamma);
    XT_HANDLE_NEW(XT_HANDLE_SCHEDULER);
    return new xt_scheduler_s{std::move(s), nullptr};)
}
xt_scheduler xt_reduce_on_plateau_new(xt_optim o, int mode_min, double factor,
                                      int patience, double threshold,
                                      int cooldown, double min_lr) {
  TRY(nullptr,
    auto mode = mode_min ? torch::optim::ReduceLROnPlateauScheduler::min
                         : torch::optim::ReduceLROnPlateauScheduler::max;
    std::vector<float> floor(1, (float) min_lr);
    auto s = std::make_unique<torch::optim::ReduceLROnPlateauScheduler>(
      *o->o, mode, (float) factor, patience, threshold,
      torch::optim::ReduceLROnPlateauScheduler::rel, cooldown, floor);
    XT_HANDLE_NEW(XT_HANDLE_SCHEDULER);
    return new xt_scheduler_s{nullptr, std::move(s)};)
}
int xt_scheduler_step(xt_scheduler s) {
  TRY(-1,
    if (!s->step_lr) {
      note_error("this scheduler advances only with a metric");
      return -1;
    }
    s->step_lr->step();)
  return 0;
}
int xt_scheduler_step_metric(xt_scheduler s, double metric) {
  TRY(-1,
    if (!s->plateau) {
      note_error("this scheduler advances without a metric");
      return -1;
    }
    s->plateau->step((float) metric);)
  return 0;
}
void xt_scheduler_free(xt_scheduler s) {
  if (s) XT_HANDLE_DROP(XT_HANDLE_SCHEDULER);
  TRY_VOID(delete s;)
}

/* Serialization */

struct xt_pickle_s {
  std::vector<std::string> names;
  std::vector<at::Tensor> tensors;
};

static void write_pickle(c10::IValue values, const char *path) {
  auto bytes = torch::jit::pickle_save(values);
  std::ofstream out(path, std::ios::binary);
  if (!out) throw std::runtime_error(std::string("cannot write ") + path);
  out.write(bytes.data(), (std::streamsize) bytes.size());
  out.close();
  if (!out) throw std::runtime_error(std::string("cannot write ") + path);
}

static c10::IValue read_pickle(const char *path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) throw std::runtime_error(std::string("cannot read ") + path);
  std::vector<char> bytes((std::istreambuf_iterator<char>(in)),
                          std::istreambuf_iterator<char>());
  return torch::jit::pickle_load(bytes);
}

/* Python's parameter IDs identify positions, never native addresses. The
   importer builds the replacement completely before changing the optimizer. */
static torch::optim::Adam &adam(xt_optim o) {
  auto *value = dynamic_cast<torch::optim::Adam *>(o->o.get());
  TORCH_CHECK(value, "Python optimizer state currently supports Adam");
  return *value;
}
static c10::impl::GenericDict dictionary() {
  return c10::impl::GenericDict(c10::AnyType::get(), c10::AnyType::get());
}
int xt_optim_save_python(xt_optim o, const char *path) {
  TRY(-1,
    auto &optimizer = adam(o);
    auto root = dictionary(), state = dictionary();
    c10::impl::GenericList groups(c10::AnyType::get());
    int64_t id = 0;
    for (auto &group : optimizer.param_groups()) {
      auto &options = static_cast<torch::optim::AdamOptions &>(group.options());
      auto values = dictionary();
      c10::List<int64_t> ids;
      for (auto &parameter : group.params()) {
        ids.push_back(id);
        auto found = optimizer.state().find(parameter.unsafeGetTensorImpl());
        if (found != optimizer.state().end()) {
          auto &saved = static_cast<torch::optim::AdamParamState &>(*found->second);
          auto fields = dictionary();
          fields.insert("step", torch::scalar_tensor(saved.step(), at::kLong));
          fields.insert("exp_avg", saved.exp_avg());
          fields.insert("exp_avg_sq", saved.exp_avg_sq());
          if (options.amsgrad())
            fields.insert("max_exp_avg_sq", saved.max_exp_avg_sq());
          state.insert(id, fields);
        }
        id++;
      }
      values.insert("params", ids);
      values.insert("lr", options.lr());
      values.insert("betas", c10::ivalue::Tuple::create(
        {std::get<0>(options.betas()), std::get<1>(options.betas())}));
      values.insert("eps", options.eps());
      values.insert("weight_decay", options.weight_decay());
      values.insert("amsgrad", options.amsgrad());
      values.insert("maximize", false);
      values.insert("foreach", false);
      values.insert("capturable", false);
      values.insert("differentiable", false);
      values.insert("fused", false);
      values.insert("decoupled_weight_decay", false);
      groups.push_back(values);
    }
    root.insert("state", state);
    root.insert("param_groups", groups);
    write_pickle(root, path);)
  return 0;
}
static at::Tensor moment(const c10::impl::GenericDict &fields,
                         const char *key, const at::Tensor &parameter) {
  auto tensor = fields.at(key).toTensor();
  TORCH_CHECK(tensor.sizes() == parameter.sizes(),
              "optimizer moment shape does not match parameter");
  TORCH_CHECK(tensor.scalar_type() == parameter.scalar_type(),
              "optimizer moment dtype does not match parameter");
  return tensor.to(parameter.device()).clone();
}
static double adam_number(c10::IValue value) {
  return value.isTensor() ? value.toTensor().item<double>()
                          : value.toScalar().toDouble();
}
static int64_t adam_step(c10::IValue value) {
  if (value.isInt()) {
    TORCH_CHECK(value.toInt() >= 0, "invalid Adam step");
    return value.toInt();
  }
  if (value.isTensor() && at::isIntegralType(value.toTensor().scalar_type(), false)) {
    int64_t step = value.toTensor().item<int64_t>();
    TORCH_CHECK(step >= 0, "invalid Adam step");
    return step;
  }
  double step = value.isTensor() ? value.toTensor().item<double>()
                                : value.toDouble();
  TORCH_CHECK(std::isfinite(step) && step >= 0 &&
              step < 9223372036854775808.0 && std::floor(step) == step,
              "invalid Adam step");
  return (int64_t) step;
}
int xt_optim_load_python(xt_optim o, const char *path) {
  TRY(-1,
    auto &optimizer = adam(o);
    auto root = read_pickle(path).toGenericDict();
    auto source = root.at("state").toGenericDict();
    std::vector<at::Tensor> parameters;
    for (auto &group : optimizer.param_groups())
      parameters.insert(parameters.end(), group.params().begin(),
                        group.params().end());
    std::vector<torch::optim::OptimizerParamGroup> groups;
    ska::flat_hash_map<void *,
      std::unique_ptr<torch::optim::OptimizerParamState>> state;
    std::unordered_set<int64_t> ids;
    size_t index = 0;
    for (auto item : root.at("param_groups").toListRef()) {
      auto fields = item.toGenericDict();
      for (auto key : {"maximize", "capturable", "differentiable",
                       "decoupled_weight_decay"}) {
        auto found = fields.find(key);
        TORCH_CHECK(found == fields.end() || !found->value().toBool(),
                    "unsupported Adam option: ", key);
      }
      auto betas = fields.at("betas").toTupleRef().elements();
      TORCH_CHECK(betas.size() == 2, "Adam needs two betas");
      auto options = std::make_unique<torch::optim::AdamOptions>(
        adam_number(fields.at("lr")));
      options->betas({adam_number(betas[0]), adam_number(betas[1])})
        .eps(adam_number(fields.at("eps")))
        .weight_decay(adam_number(fields.at("weight_decay")))
        .amsgrad(fields.at("amsgrad").toBool());
      TORCH_CHECK(std::isfinite(options->lr()) && options->lr() >= 0 &&
                  std::isfinite(options->eps()) && options->eps() >= 0 &&
                  std::isfinite(options->weight_decay()) &&
                  options->weight_decay() >= 0 &&
                  std::get<0>(options->betas()) >= 0 &&
                  std::get<0>(options->betas()) < 1 &&
                  std::get<1>(options->betas()) >= 0 &&
                  std::get<1>(options->betas()) < 1, "invalid Adam options");
      std::vector<at::Tensor> group_parameters;
      for (auto entry : fields.at("params").toListRef()) {
        int64_t id = entry.toInt();
        TORCH_CHECK(ids.insert(id).second, "duplicate optimizer parameter ID");
        TORCH_CHECK(index < parameters.size(), "too many optimizer parameters");
        auto parameter = parameters[index++];
        group_parameters.push_back(parameter);
        auto found = source.find(id);
        if (found == source.end()) continue;
        auto saved = found->value().toGenericDict();
        auto value = std::make_unique<torch::optim::AdamParamState>();
        value->step(adam_step(saved.at("step")))
          .exp_avg(moment(saved, "exp_avg", parameter))
          .exp_avg_sq(moment(saved, "exp_avg_sq", parameter));
        if (options->amsgrad()) value->max_exp_avg_sq(
          moment(saved, "max_exp_avg_sq", parameter));
        state[parameter.unsafeGetTensorImpl()] = std::move(value);
      }
      groups.emplace_back(std::move(group_parameters), std::move(options));
    }
    TORCH_CHECK(index == parameters.size(), "too few optimizer parameters");
    for (const auto &entry : source)
      TORCH_CHECK(ids.count(entry.key().toInt()), "unknown optimizer state ID");
    optimizer.param_groups() = std::move(groups);
    optimizer.state() = std::move(state);)
  return 0;
}

int xt_module_save_pickle(xt_module m, const char *path) {
  TRY(-1,
    c10::Dict<std::string, at::Tensor> values;
    for (const auto &p : m->m->named_parameters(true))
      values.insert(p.key(), p.value().detach().clone());
    for (const auto &b : m->m->named_buffers(true))
      values.insert(b.key(), b.value().detach().clone());
    write_pickle(values, path);)
  return 0;
}
int xt_module_load_pickle(xt_module m, const char *path) {
  TRY(-1,
    auto values = read_pickle(path).toGenericDict();
    torch::NoGradGuard hold;
    for (auto &p : m->m->named_parameters(true)) {
      auto found = values.find(p.key());
      if (found == values.end()) {
        note_error("checkpoint has no entry named " + p.key());
        return -1;
      }
      p.value().copy_(found->value().toTensor());
    }
    for (auto &b : m->m->named_buffers(true)) {
      auto found = values.find(b.key());
      if (found == values.end()) {
        note_error("checkpoint has no entry named " + b.key());
        return -1;
      }
      b.value().copy_(found->value().toTensor());
    })
  return 0;
}
int xt_module_save_archive(xt_module m, const char *path) {
  TRY(-1,
    torch::serialize::OutputArchive archive;
    m->m->save(archive);
    archive.save_to(path);)
  return 0;
}
int xt_module_load_archive(xt_module m, const char *path) {
  TRY(-1,
    torch::serialize::InputArchive archive;
    archive.load_from(path);
    m->m->load(archive);)
  return 0;
}
int xt_tensors_save_pickle(const char **names, xt_tensor *tensors, int count,
                           const char *path) {
  TRY(-1,
    c10::Dict<std::string, at::Tensor> values;
    for (int i = 0; i < count; i++)
      values.insert(names[i], tensors[i]->t.detach().clone());
    write_pickle(values, path);)
  return 0;
}
xt_pickle xt_pickle_open(const char *path) {
  TRY(nullptr,
    auto values = read_pickle(path).toGenericDict();
    auto opened = std::make_unique<xt_pickle_s>();
    for (const auto &entry : values) {
      opened->names.push_back(entry.key().toStringRef());
      opened->tensors.push_back(entry.value().toTensor());
    }
    XT_HANDLE_NEW(XT_HANDLE_PICKLE);
    return opened.release();)
}
int xt_pickle_count(xt_pickle p, int64_t *out) {
  *out = (int64_t) p->names.size();
  return 0;
}
const char *xt_pickle_name(xt_pickle p, int64_t index) {
  if (index < 0 || index >= (int64_t) p->names.size()) {
    note_error("pickle entry index out of range");
    return nullptr;
  }
  return p->names[(size_t) index].c_str();
}
xt_tensor xt_pickle_tensor(xt_pickle p, int64_t index) {
  if (index < 0 || index >= (int64_t) p->tensors.size()) {
    note_error("pickle entry index out of range");
    return nullptr;
  }
  TRY(nullptr, return wrap(p->tensors[(size_t) index]);)
}
void xt_pickle_free(xt_pickle p) {
  if (p) XT_HANDLE_DROP(XT_HANDLE_PICKLE);
  TRY_VOID(delete p;)
}

/* Datasets */

int xt_mnist_load(const char *root, int train, xt_tensor *images,
                  xt_tensor *targets) {
  TRY(-1,
    auto mode = train ? torch::data::datasets::MNIST::Mode::kTrain
                      : torch::data::datasets::MNIST::Mode::kTest;
    torch::data::datasets::MNIST set(root, mode);
    *images = wrap(set.images());
    *targets = wrap(set.targets());)
  return 0;
}

/* TorchScript */

struct xt_jit_s { torch::jit::Module m; };

xt_jit_module xt_jit_load(const char *path) {
  TRY(nullptr,
    XT_HANDLE_NEW(XT_HANDLE_JIT);
    return new xt_jit_s{torch::jit::load(path)};)
}
int xt_jit_forward(xt_jit_module m, xt_tensor *inputs, int count,
                   xt_tensor *outputs, int capacity, int *produced) {
  TRY(-1,
    std::vector<c10::IValue> arguments;
    arguments.reserve((size_t) (count > 0 ? count : 0));
    for (int i = 0; i < count; i++) arguments.push_back(inputs[i]->t);
    auto result = m->m.forward(arguments);
    std::vector<at::Tensor> values;
    if (result.isTensor()) {
      values.push_back(result.toTensor());
    }
    else if (result.isTuple()) {
      for (const auto &element : result.toTuple()->elements()) {
        if (!element.isTensor()) {
          note_error("a tuple element of the result is not a tensor");
          return -1;
        }
        values.push_back(element.toTensor());
      }
    }
    else {
      note_error("the result is neither a tensor nor a tuple of tensors");
      return -1;
    }
    if ((int) values.size() > capacity) {
      note_error("the result has more tensors than the caller expects");
      return -1;
    }
    for (size_t i = 0; i < values.size(); i++) outputs[i] = wrap(values[i]);
    *produced = (int) values.size();)
  return 0;
}
int xt_jit_train(xt_jit_module m, int on) {
  TRY(-1, m->m.train(on != 0);) return 0;
}
void xt_jit_free(xt_jit_module m) {
  if (m) XT_HANDLE_DROP(XT_HANDLE_JIT);
  TRY_VOID(delete m;)
}

}
