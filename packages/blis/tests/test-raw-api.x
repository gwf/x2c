/*  test-raw-api.x -- Direct BLIS object, view, typed, and profile calls. */

#include "blis-21.h"
#include "test-support.x"
#include <math.h>
#include <string.h>

$(import "../../../unittest/test-macros.xmacro")

static void blis_raw_object_and_view_api(void) {
  obj_t matrix;
  bli_obj_create(BLIS_DOUBLE, 2, 2, 0, 0, &matrix);
  defer bli_obj_free(&matrix);
  bli_setijm(1.0, 0.0, 0, 0, &matrix);
  bli_setijm(2.0, 0.0, 1, 0, &matrix);
  bli_setijm(3.0, 0.0, 0, 1, &matrix);
  bli_setijm(4.0, 0.0, 1, 1, &matrix);

  obj_t column;
  bli_acquire_mpart(0, 1, 2, 1, &matrix, &column);
  bli_setijm(8.0, 0.0, 0, 0, &column);
  double real = 0.0, imaginary = 0.0;
  EXPECT_INT_EQ(bli_getijm(0, 1, &matrix, &real, &imaginary), BLIS_SUCCESS);
  EXPECT_TRUE(fabs(real - 8.0) < 1e-12);

  obj_t transposed;
  bli_obj_alias_to(&matrix, &transposed);
  bli_obj_induce_trans(&transposed);
  EXPECT_INT_EQ(bli_obj_length(&transposed), 2);
  EXPECT_INT_EQ(bli_obj_row_stride(&transposed), bli_obj_col_stride(&matrix));
}

static void blis_raw_mixed_object_gemm(void) {
  obj_t left, right, destination;
  bli_obj_create(BLIS_FLOAT, 1, 2, 0, 0, &left);
  defer bli_obj_free(&left);
  bli_obj_create(BLIS_FLOAT, 2, 1, 0, 0, &right);
  defer bli_obj_free(&right);
  bli_obj_create(BLIS_DOUBLE, 1, 1, 0, 0, &destination);
  defer bli_obj_free(&destination);
  bli_obj_set_comp_prec(BLIS_DOUBLE_PREC, &destination);

  bli_setijm(2.0, 0.0, 0, 0, &left);
  bli_setijm(3.0, 0.0, 0, 1, &left);
  bli_setijm(4.0, 0.0, 0, 0, &right);
  bli_setijm(5.0, 0.0, 1, 0, &right);
  bli_setm(&BLIS_ONE, &destination);
  bli_gemm(&BLIS_ONE, &left, &right, &BLIS_ONE, &destination);

  double real = 0.0, imaginary = 0.0;
  EXPECT_INT_EQ(
    bli_getijm(0, 0, &destination, &real, &imaginary), BLIS_SUCCESS
  );
  EXPECT_TRUE(fabs(real - 24.0) < 1e-12);
  EXPECT_INT_EQ(bli_obj_comp_prec(&destination), BLIS_DOUBLE_PREC);
}

static void blis_raw_typed_api(void) {
  double left[4] = { 1.0, 3.0, 2.0, 4.0 };
  double right[4] = { 5.0, 7.0, 6.0, 8.0 };
  double product[4] = { 0.0 };
  double alpha = 1.0;
  double beta = 0.0;

  bli_dgemm(
    BLIS_NO_TRANSPOSE, BLIS_NO_TRANSPOSE, 2, 2, 2,
    &alpha, left, 1, 2, right, 1, 2, &beta, product, 1, 2
  );
  EXPECT_TRUE(fabs(product[0] - 19.0) < 1e-12);
  EXPECT_TRUE(fabs(product[3] - 50.0) < 1e-12);
  EXPECT_NOT_NULL((void *) bli_dgemv);
}

static void blis_raw_profile(void) {
  EXPECT_TRUE(!strncmp(bli_info_get_version_str(), "2.1", 3));
  EXPECT_INT_EQ(bli_info_get_enable_blas(), 0);
  EXPECT_INT_EQ(bli_info_get_enable_cblas(), 0);
  EXPECT_INT_EQ(bli_info_get_enable_threading(), 0);
  EXPECT_INT_EQ(bli_info_get_enable_openmp(), 0);
  EXPECT_INT_EQ(bli_info_get_enable_pthreads(), 0);
}

void blis_raw_suite(void) {
  $test.run(blis_raw_object_and_view_api);
  $test.run(blis_raw_mixed_object_gemm);
  $test.run(blis_raw_typed_api);
  $test.run(blis_raw_profile);
}

int main(void) {
  bli_init();
  defer bli_finalize();
  TestHarness_begin();
  $test.suite(blis_raw_suite);
  return TestHarness_finish();
}
