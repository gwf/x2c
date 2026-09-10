/*  torch-2.10.h -- the C ABI this package compiles over libtorch 2.10.

    Every handle owns one libtorch object and is freed by the matching
    *_free. libtorch reports failure by throwing, and a C++ exception must
    not cross this boundary, so every entry point catches:

    - a function returning a handle returns NULL on failure;
    - a function producing a scalar returns int, 0 on success and nonzero
      on failure, and writes its result through an out parameter;
    - only the diagnostic readers and the *_free functions return void or a
      value directly, because they cannot fail.

    After a failure xt_last_error holds the first line of the libtorch
    message for the calling thread and xt_last_error_full holds all of it.

    Integer values cross as int64_t and floating values as double; a caller
    holding an integer tensor uses the int64 entry points to stay exact.
*/
#ifndef X2C_TORCH_2_10_H
#define X2C_TORCH_2_10_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct xt_tensor_s *xt_tensor;

/* c10::ScalarType values for the pinned version; checked in the shim. */
enum xt_dtype {
  XT_UINT8 = 0, XT_INT8 = 1, XT_INT16 = 2, XT_INT32 = 3, XT_INT64 = 4,
  XT_FLOAT16 = 5, XT_FLOAT32 = 6, XT_FLOAT64 = 7, XT_BOOL = 11
};

const char *xt_last_error(void);
const char *xt_last_error_full(void);
const char *xt_version(void);
int xt_manual_seed(int64_t seed);
int xt_set_num_threads(int count);
int xt_get_num_threads(int *out);
int xt_set_num_interop_threads(int count);
int xt_get_num_interop_threads(int *out);

/* creation; shape is rank int64 sizes */
xt_tensor xt_from_doubles(const double *data, const int64_t *shape, int rank,
                          int dtype);
xt_tensor xt_from_int64s(const int64_t *data, const int64_t *shape, int rank,
                         int dtype);
xt_tensor xt_scalar(double value, int dtype);
xt_tensor xt_scalar_int64(int64_t value, int dtype);
xt_tensor xt_zeros(const int64_t *shape, int rank, int dtype);
xt_tensor xt_ones(const int64_t *shape, int rank, int dtype);
xt_tensor xt_full(const int64_t *shape, int rank, double value, int dtype);
xt_tensor xt_rand(const int64_t *shape, int rank, int dtype);
xt_tensor xt_randn(const int64_t *shape, int rank, int dtype);
xt_tensor xt_arange(double start, double end, double step, int dtype);
xt_tensor xt_randperm(int64_t n);

/* queries */
int xt_rank(xt_tensor a, int *out);
int xt_size(xt_tensor a, int dim, int64_t *out);
int xt_numel(xt_tensor a, int64_t *out);
int xt_dtype(xt_tensor a, int *out);
int xt_requires_grad(xt_tensor a, int *out);
int xt_is_leaf(xt_tensor a, int *out);
int xt_item_double(xt_tensor a, double *out);
int xt_item_int64(xt_tensor a, int64_t *out);
int xt_copy_out_doubles(xt_tensor a, double *out, int64_t count);
int xt_copy_out_int64s(xt_tensor a, int64_t *out, int64_t count);
const char *xt_str(xt_tensor a);

/* elementwise and reductions; every result is a new handle */
xt_tensor xt_add(xt_tensor a, xt_tensor b);
xt_tensor xt_sub(xt_tensor a, xt_tensor b);
xt_tensor xt_mul(xt_tensor a, xt_tensor b);
xt_tensor xt_div(xt_tensor a, xt_tensor b);
xt_tensor xt_matmul(xt_tensor a, xt_tensor b);
xt_tensor xt_pow(xt_tensor a, double exponent);
xt_tensor xt_neg(xt_tensor a);
xt_tensor xt_abs(xt_tensor a);
xt_tensor xt_exp(xt_tensor a);
xt_tensor xt_log(xt_tensor a);
xt_tensor xt_sqrt(xt_tensor a);
xt_tensor xt_tanh(xt_tensor a);
xt_tensor xt_sigmoid(xt_tensor a);
xt_tensor xt_relu(xt_tensor a);
xt_tensor xt_sum(xt_tensor a);
xt_tensor xt_mean(xt_tensor a);
xt_tensor xt_sum_dim(xt_tensor a, int dim, int keepdim);
xt_tensor xt_mean_dim(xt_tensor a, int dim, int keepdim);
xt_tensor xt_max_all(xt_tensor a);
xt_tensor xt_min_all(xt_tensor a);
xt_tensor xt_argmax(xt_tensor a, int dim, int keepdim);
xt_tensor xt_softmax(xt_tensor a, int dim);
xt_tensor xt_log_softmax(xt_tensor a, int dim);
int xt_allclose(xt_tensor a, xt_tensor b, double rtol, double atol, int *out);
int xt_equal(xt_tensor a, xt_tensor b, int *out);

/* losses; a target of class indexes is int64 */
xt_tensor xt_mse_loss(xt_tensor input, xt_tensor target);
xt_tensor xt_cross_entropy(xt_tensor logits, xt_tensor targets);
xt_tensor xt_nll_loss(xt_tensor log_probabilities, xt_tensor targets);
xt_tensor xt_bce_with_logits(xt_tensor logits, xt_tensor targets);

/* comparison and selection; comparisons produce bool tensors */
xt_tensor xt_eq(xt_tensor a, xt_tensor b);
xt_tensor xt_gt(xt_tensor a, xt_tensor b);
xt_tensor xt_lt(xt_tensor a, xt_tensor b);
xt_tensor xt_to_bool(xt_tensor a);
xt_tensor xt_masked_select(xt_tensor a, xt_tensor mask);
xt_tensor xt_where(xt_tensor condition, xt_tensor a, xt_tensor b);

/* shape and indexing; views share storage with their source */
xt_tensor xt_reshape(xt_tensor a, const int64_t *shape, int rank);
xt_tensor xt_transpose(xt_tensor a, int dim0, int dim1);
xt_tensor xt_squeeze(xt_tensor a, int dim);
xt_tensor xt_unsqueeze(xt_tensor a, int dim);
xt_tensor xt_select(xt_tensor a, int dim, int64_t index);
xt_tensor xt_slice(xt_tensor a, int dim, int64_t start, int64_t end,
                   int64_t step);
xt_tensor xt_narrow(xt_tensor a, int dim, int64_t start, int64_t length);
xt_tensor xt_flatten(xt_tensor a, int start, int end);
xt_tensor xt_index_select(xt_tensor a, int dim, xt_tensor indexes);
xt_tensor xt_cat(xt_tensor *tensors, int count, int dim);
xt_tensor xt_stack(xt_tensor *tensors, int count, int dim);
xt_tensor xt_to_dtype(xt_tensor a, int dtype);
xt_tensor xt_clone(xt_tensor a);
xt_tensor xt_contiguous(xt_tensor a);

/* autograd */
xt_tensor xt_requires_grad_(xt_tensor a, int on);
xt_tensor xt_detach(xt_tensor a);
int xt_backward(xt_tensor a);
xt_tensor xt_grad(xt_tensor a);
int xt_zero_grad(xt_tensor a);
int xt_add_(xt_tensor a, xt_tensor b, double alpha);
int xt_copy_(xt_tensor dst, xt_tensor src);
int xt_no_grad_push(void);
int xt_no_grad_pop(void);
int xt_grad_enabled(int *out);

/* Inference mode is stronger than no-grad: results carry no autograd
   metadata at all, so version counting stops as well. */
int xt_inference_mode_push(void);
int xt_inference_mode_pop(void);

void xt_tensor_free(xt_tensor a);

/* Modules.

   A module handle shares ownership of one torch::nn::Module. A child
   fetched by name is a second handle onto the same object, so freeing it
   does not detach it from its parent. Parameter and buffer enumeration is
   recursive and uses libtorch's qualified names, the same strings Python's
   state_dict() uses. A name returned by this API stays valid until the
   next name query on the same handle.
*/
typedef struct xt_module_s *xt_module;

xt_module xt_linear_new(int64_t in_features, int64_t out_features, int bias);

/* Native layers. Every constructor takes the arguments PyTorch's
   constructor takes, in the same order, so a caller reads the same shape
   here as in Python. Parameter and buffer names match Python's too. */
xt_module xt_conv1d_new(int64_t in_channels, int64_t out_channels,
                        int64_t kernel, int64_t stride, int64_t padding,
                        int64_t dilation, int64_t groups, int bias);
xt_module xt_conv2d_new(int64_t in_channels, int64_t out_channels,
                        int64_t kernel, int64_t stride, int64_t padding,
                        int64_t dilation, int64_t groups, int bias);
xt_module xt_batch_norm1d_new(int64_t features, double eps, double momentum,
                              int affine, int track_running_stats);
xt_module xt_batch_norm2d_new(int64_t features, double eps, double momentum,
                              int affine, int track_running_stats);
xt_module xt_layer_norm_new(const int64_t *shape, int rank, double eps,
                            int affine);
xt_module xt_dropout_new(double p);
xt_module xt_embedding_new(int64_t num_embeddings, int64_t dim);
xt_module xt_lstm_new(int64_t input_size, int64_t hidden_size,
                      int64_t layers, int batch_first);
xt_module xt_gru_new(int64_t input_size, int64_t hidden_size, int64_t layers,
                     int batch_first);
xt_module xt_max_pool2d_new(int64_t kernel, int64_t stride, int64_t padding);
xt_module xt_avg_pool2d_new(int64_t kernel, int64_t stride, int64_t padding);
xt_module xt_flatten_new(int64_t start_dim, int64_t end_dim);
xt_module xt_relu_new(void);
xt_module xt_tanh_new(void);
xt_module xt_sigmoid_new(void);

/* A sequential root forwards its registered children in registration
   order; register them with xt_module_register_module under the names
   PyTorch would use, "0", "1", and so on. */
xt_module xt_sequential_new(void);
xt_module xt_composed_new(void);
int xt_module_register_module(xt_module parent, const char *name,
                              xt_module child);
int xt_module_register_parameter(xt_module parent, const char *name,
                                 xt_tensor value, int requires_grad);
int xt_module_register_buffer(xt_module parent, const char *name,
                              xt_tensor value);
xt_module xt_module_child(xt_module parent, const char *name);
xt_tensor xt_module_forward(xt_module m, xt_tensor input);
/* The recurrent layers return a sequence and their final state: an LSTM
   writes both hidden and cell, a GRU writes hidden and leaves *cell
   NULL. Every written handle is new. */
int xt_rnn_forward(xt_module m, xt_tensor input, xt_tensor *output,
                   xt_tensor *hidden, xt_tensor *cell);
int xt_module_child_count(xt_module m, int64_t *out);
int xt_module_parameter_count(xt_module m, int64_t *out);
const char *xt_module_parameter_name(xt_module m, int64_t index);
xt_tensor xt_module_parameter(xt_module m, int64_t index);
int xt_module_buffer_count(xt_module m, int64_t *out);
const char *xt_module_buffer_name(xt_module m, int64_t index);
xt_tensor xt_module_buffer(xt_module m, int64_t index);
int xt_module_train(xt_module m, int on);
int xt_module_is_training(xt_module m, int *out);
int xt_module_zero_grad(xt_module m);
int xt_module_to_dtype(xt_module m, int dtype);
void xt_module_free(xt_module m);

/* Optimizers.

   An optimizer holds references to the parameter tensors it was built
   over; those tensors must outlive it. Learning-rate get and set cover
   every parameter group.
*/
typedef struct xt_optim_s *xt_optim;

enum xt_optim_kind {
  XT_SGD = 0, XT_ADAM = 1, XT_ADAMW = 2, XT_RMSPROP = 3, XT_ADAGRAD = 4
};

xt_optim xt_sgd_new(xt_module m, double lr, double momentum,
                    double weight_decay, int nesterov);
xt_optim xt_adam_new(xt_module m, double lr, double beta1, double beta2,
                     double eps, double weight_decay, int amsgrad);
xt_optim xt_adamw_new(xt_module m, double lr, double beta1, double beta2,
                      double eps, double weight_decay, int amsgrad);
xt_optim xt_rmsprop_new(xt_module m, double lr, double alpha, double eps,
                        double weight_decay, double momentum);
xt_optim xt_adagrad_new(xt_module m, double lr, double weight_decay);
xt_optim xt_optim_new_from_tensors(int kind, xt_tensor *tensors, int count,
                                   double lr);
int xt_optim_zero_grad(xt_optim o);
int xt_optim_step(xt_optim o);
int xt_optim_lr(xt_optim o, double *out);
int xt_optim_set_lr(xt_optim o, double lr);
int xt_optim_save(xt_optim o, const char *path);
int xt_optim_load(xt_optim o, const char *path);
void xt_optim_free(xt_optim o);

/* Learning-rate schedules; libtorch ships exactly these two, and they have
   no common base, so one handle carries whichever is present. A scheduler
   refers to its optimizer, which must outlive it. StepLR advances with
   xt_scheduler_step; ReduceLROnPlateau advances with a metric.
*/
typedef struct xt_scheduler_s *xt_scheduler;

xt_scheduler xt_step_lr_new(xt_optim o, int step_size, double gamma);
xt_scheduler xt_reduce_on_plateau_new(xt_optim o, int mode_min, double factor,
                                      int patience, double threshold,
                                      int cooldown, double min_lr);
int xt_scheduler_step(xt_scheduler s);
int xt_scheduler_step_metric(xt_scheduler s, double metric);
void xt_scheduler_free(xt_scheduler s);

/* Serialization.

   The pickle path writes a Dict<string, Tensor> through
   torch::jit::pickle_save; Python reads it with torch.load, and Python
   must write dict(model.state_dict()) for the reverse direction. The
   archive path is torch::save/load, which Python reads only through
   torch.jit.load.
*/
typedef struct xt_pickle_s *xt_pickle;

int xt_module_save_pickle(xt_module m, const char *path);
int xt_module_load_pickle(xt_module m, const char *path);
int xt_module_save_archive(xt_module m, const char *path);
int xt_module_load_archive(xt_module m, const char *path);
int xt_tensors_save_pickle(const char **names, xt_tensor *tensors, int count,
                           const char *path);
xt_pickle xt_pickle_open(const char *path);
int xt_pickle_count(xt_pickle p, int64_t *out);
const char *xt_pickle_name(xt_pickle p, int64_t index);
xt_tensor xt_pickle_tensor(xt_pickle p, int64_t index);
void xt_pickle_free(xt_pickle p);

/* Datasets.

   torch::data::datasets::MNIST reads the four IDX files under root by
   their standard names. The images cross as one N x 1 x 28 x 28 float32
   tensor scaled to [0, 1] and the targets as N int64 classes.
*/
int xt_mnist_load(const char *root, int train, xt_tensor *images,
                  xt_tensor *targets);

/* TorchScript.

   x2c loads and runs a module scripted or traced in Python; it cannot
   produce one. Inputs and outputs cross as tensors: a forward returning a
   tuple of tensors writes each element, and *produced reports how many.
   A result that is neither a tensor nor a tuple of tensors fails.
*/
typedef struct xt_jit_s *xt_jit_module;

xt_jit_module xt_jit_load(const char *path);
int xt_jit_forward(xt_jit_module m, xt_tensor *inputs, int count,
                   xt_tensor *outputs, int capacity, int *produced);
int xt_jit_train(xt_jit_module m, int on);
void xt_jit_free(xt_jit_module m);

#ifdef __cplusplus
}
#endif
#endif
