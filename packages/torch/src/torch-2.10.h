/*  torch-2.10.h -- the C ABI this package compiles over libtorch 2.10.

    Every handle owns one libtorch object and is freed by the matching
    *_free. A function that returns a handle returns NULL on failure and a
    function that returns a status returns nonzero; xt_last_error then holds
    the first line of the libtorch message for the calling thread.
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
void xt_manual_seed(int64_t seed);
void xt_set_num_threads(int count);
int xt_get_num_threads(void);

/* creation; shape is rank int64 sizes */
xt_tensor xt_from_doubles(const double *data, const int64_t *shape, int rank,
                          int dtype);
xt_tensor xt_scalar(double value, int dtype);
xt_tensor xt_zeros(const int64_t *shape, int rank, int dtype);
xt_tensor xt_ones(const int64_t *shape, int rank, int dtype);
xt_tensor xt_full(const int64_t *shape, int rank, double value, int dtype);
xt_tensor xt_rand(const int64_t *shape, int rank, int dtype);
xt_tensor xt_randn(const int64_t *shape, int rank, int dtype);
xt_tensor xt_arange(double start, double end, double step, int dtype);

/* queries */
int xt_rank(xt_tensor a);
int64_t xt_size(xt_tensor a, int dim);
int64_t xt_numel(xt_tensor a);
int xt_dtype(xt_tensor a);
int xt_requires_grad(xt_tensor a);
int xt_is_leaf(xt_tensor a);
double xt_item(xt_tensor a);
void xt_copy_out_doubles(xt_tensor a, double *out, int64_t count);
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
xt_tensor xt_mse_loss(xt_tensor input, xt_tensor target);
int xt_allclose(xt_tensor a, xt_tensor b, double rtol, double atol);
int xt_equal(xt_tensor a, xt_tensor b);

/* shape and indexing; views share storage with their source */
xt_tensor xt_reshape(xt_tensor a, const int64_t *shape, int rank);
xt_tensor xt_transpose(xt_tensor a, int dim0, int dim1);
xt_tensor xt_squeeze(xt_tensor a, int dim);
xt_tensor xt_unsqueeze(xt_tensor a, int dim);
xt_tensor xt_select(xt_tensor a, int dim, int64_t index);
xt_tensor xt_slice(xt_tensor a, int dim, int64_t start, int64_t end,
                   int64_t step);
xt_tensor xt_index_select(xt_tensor a, int dim, xt_tensor indexes);
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
void xt_no_grad_push(void);
void xt_no_grad_pop(void);
int xt_grad_enabled(void);

void xt_tensor_free(xt_tensor a);

#ifdef __cplusplus
}
#endif
#endif
