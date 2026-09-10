/*  test-blis.x -- Focused tests for owned BLIS objects and views. */

import "blis" with Blis, BlisObject;

#include "test-support.x"
#include <math.h>

$(import "../../../unittest/test-macros.xmacro")

#define EXPECT_NEAR(actual, expected, tolerance) \
  EXPECT_TRUE(fabs((actual) - (expected)) < (tolerance))

static void blis_application_path(void) {
  BlisObject observations = BlisObject.copy_rows(%(
    (0.123456789 1.0 5.0)
    (0.223456789 3.0 5.0)
    (-0.076543211 5.0 5.0)
    (0.323456789 7.0 5.0)
  ), BLIS_FLOAT);
  defer observations.free();
  BlisObject ones = BlisObject.copy_vector(%(1.0 1.0 1.0 1.0), BLIS_FLOAT);
  defer ones.free();

  for (int index = 0; index < observations.columns(); index++) {
    BlisObject column = observations.column(index);
    double mean = column.dotv(ones) / column.length();
    EXPECT_NOT_NULL(column.axpyv(-mean, ones));
  }
  EXPECT_NEAR(observations.column(2).normfv(), 0.0, 1e-12);

  BlisObject transposed = observations.transpose_view();
  BlisObject risk = BlisObject.new(BLIS_DOUBLE, 3, 3);
  defer risk.free();
  risk.fill(0.25).set_computation_precision(BLIS_DOUBLE_PREC);
  EXPECT_NOT_NULL(risk.gemm(1.0 / 3.0, transposed, observations, 0.5));

  EXPECT_NEAR(risk.at(0, 0), 0.1541667, 1e-6);
  EXPECT_NEAR(risk.at(0, 1), 0.225, 1e-6);
  EXPECT_NEAR(risk.at(1, 1), 6.7916667, 1e-6);
  EXPECT_NEAR(risk.at(2, 2), 0.125, 1e-12);
}

static void blis_views_alias_and_describe_owner_storage(void) {
  BlisObject matrix = BlisObject.copy_rows(
    %((1.0 2.0 3.0) (4.0 5.0 6.0)), BLIS_DOUBLE
  );
  defer matrix.free();
  BlisObject column = matrix.column(-1), transposed = matrix.transpose_view();

  EXPECT_TRUE(column.is_view());
  EXPECT_TRUE(column.orientation() == <column>);
  EXPECT_INT_EQ(column.rows(), 2);
  EXPECT_INT_EQ(column.columns(), 1);
  EXPECT_INT_EQ(column.row_offset(), 0);
  EXPECT_INT_EQ(column.column_offset(), 2);
  EXPECT_FALSE(column.transposed());

  EXPECT_TRUE(transposed.is_view());
  EXPECT_TRUE(transposed.transposed());
  EXPECT_INT_EQ(transposed.rows(), 3);
  EXPECT_INT_EQ(transposed.columns(), 2);
  EXPECT_INT_EQ(transposed.row_stride(), matrix.column_stride());
  EXPECT_INT_EQ(transposed.column_stride(), matrix.row_stride());

  column.put(1, 0, 9.0);
  EXPECT_NEAR(matrix.at(1, 2), 9.0, 1e-12);
  matrix.put(0, 2, 8.0);
  EXPECT_NEAR(column.at(0, 0), 8.0, 1e-12);
  EXPECT_NEAR(transposed.at(2, 0), 8.0, 1e-12);

  BlisObject nested = matrix.part(0, 1, 2, 2).column(0);
  EXPECT_INT_EQ(nested.row_offset(), 0);
  EXPECT_INT_EQ(nested.column_offset(), 1);
  EXPECT_NEAR(nested.at(1, 0), 5.0, 1e-12);
  EXPECT_TRUE(nested.native() != NULL);
}

static void blis_owner_release_invalidates_views(void) {
  BlisObject owner = BlisObject.copy_rows(%((1.0 2.0)), BLIS_DOUBLE);
  BlisObject view = owner.column(0);

  int view_free_caught = 0;
  try view.free();
  catch %(bad-state *detail): {
    view_free_caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"free");
  }
  EXPECT_TRUE(view_free_caught);
  EXPECT_NEAR(owner.at(0, 0), 1.0, 1e-12);

  EXPECT_NULL(owner.free());
  EXPECT_NULL(owner.free());
  int stale_caught = 0;
  try view.at(0, 0);
  catch %(bad-state *detail): {
    stale_caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"BLIS");
  }
  EXPECT_TRUE(stale_caught);
}

static void blis_collection_boundary_is_a_precision_copy(void) {
  List rows = %((0.123456789 2.0));
  BlisObject copied = BlisObject.copy_rows(rows, BLIS_FLOAT);
  defer copied.free();

  EXPECT_STR_EQ(copied.storage_precision(), %"single");
  EXPECT_TRUE(copied.at(0, 0) != rows.car().car().double());
  EXPECT_NEAR(copied.at(0, 0), (double) (float) 0.123456789, 1e-12);
  copied.put(0, 1, 7.0);
  EXPECT_NEAR(rows.car().cadr().double(), 2.0, 1e-12);

  BlisObject result = BlisObject.new(BLIS_DOUBLE, 1, 1);
  defer result.free();
  EXPECT_STR_EQ(result.storage_precision(), %"double");
  EXPECT_STR_EQ(result.computation_precision(), %"double");
  result.set_computation_precision(BLIS_SINGLE_PREC);
  EXPECT_STR_EQ(result.computation_precision(), %"single");

  int precision_caught = 0;
  try result.set_computation_precision((prec_t) -1);
  catch %(bad-arg *detail): {
    precision_caught = 1;
    EXPECT_STR_EQ(
      detail.assoc(<operation>).string(), %"set_computation_precision"
    );
  }
  EXPECT_TRUE(precision_caught);
}

static void blis_collection_copy_converts_every_numeric_tag(void) {
  float single = 1.25f;
  long double wide = 2.5L;
  BlisObject copied = BlisObject.copy_vector(%(3 $single $wide), BLIS_DOUBLE);
  defer copied.free();

  EXPECT_NEAR(copied.at(0, 0), 3.0, 1e-12);
  EXPECT_NEAR(copied.at(1, 0), 1.25, 1e-12);
  EXPECT_NEAR(copied.at(2, 0), 2.5, 1e-12);

  Var exceptional = Var.box_long_double(0.0L / 0.0L);
  int exceptional_caught = 0;
  try BlisObject.copy_vector(%($exceptional), BLIS_DOUBLE);
  catch %(bad-arg *detail): {
    exceptional_caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"copy_vector");
  }
  EXPECT_TRUE(exceptional_caught);

  Var infinity = Var.box_long_double(1.0L / 0.0L);
  exceptional_caught = 0;
  try BlisObject.copy_vector(%($infinity), BLIS_DOUBLE);
  catch %(bad-arg *detail): {
    exceptional_caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"copy_vector");
  }
  EXPECT_TRUE(exceptional_caught);
}

static void blis_operators_are_scoped_blis_operations(void) {
  BlisObject left = BlisObject.copy_rows(%((1 2) (3 4)), BLIS_DOUBLE);
  defer left.free();
  BlisObject right = BlisObject.copy_rows(%((2 0) (1 2)), BLIS_DOUBLE);
  defer right.free();
  ScopeStats before = Scope.stats();
  Scope.retain();
  {
    defer Scope.release();
    BlisObject sum = left + right;
    EXPECT_NEAR(sum.at(0, 0), 3.0, 1e-12);
    BlisObject restored = sum - right;
    EXPECT_NEAR(restored.at(1, 1), 4.0, 1e-12);

    BlisObject result = -(left @ right + left - right);
    EXPECT_INT_EQ(result.rows(), 2);
    EXPECT_INT_EQ(result.columns(), 2);
    EXPECT_NEAR(result.at(0, 0), -3.0, 1e-12);
    EXPECT_NEAR(result.at(0, 1), -6.0, 1e-12);
    EXPECT_NEAR(result.at(1, 0), -12.0, 1e-12);
    EXPECT_NEAR(result.at(1, 1), -10.0, 1e-12);
  }
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ((int) after.live_allocations, (int) before.live_allocations);

  BlisObject wrong = BlisObject.copy_rows(%((1 2 3)), BLIS_DOUBLE);
  defer wrong.free();
  int shape_caught = 0;
  try left @ wrong;
  catch %(bad-arg *detail): {
    shape_caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"matmul");
  }
  EXPECT_TRUE(shape_caught);
}

static void blis_dimensions_empty_views_and_bounds(void) {
  BlisObject empty = BlisObject.new(BLIS_DOUBLE, 0, 3);
  defer empty.free();
  EXPECT_INT_EQ(empty.rows(), 0);
  EXPECT_INT_EQ(empty.columns(), 3);
  BlisObject empty_column = empty.column(1);
  EXPECT_INT_EQ(empty_column.length(), 0);

  BlisObject matrix = BlisObject.copy_rows(
    %((1.0 2.0 3.0) (4.0 5.0 6.0)), BLIS_DOUBLE
  );
  defer matrix.free();
  BlisObject part = matrix.part(0, 1, 2, 2);
  EXPECT_INT_EQ(part.rows(), 2);
  EXPECT_INT_EQ(part.columns(), 2);
  EXPECT_NEAR(part.at(-1, -1), 6.0, 1e-12);

  int bounds_caught = 0;
  try matrix.part(0, 2, 2, 2);
  catch %(bad-arg *detail): {
    bounds_caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"part");
  }
  EXPECT_TRUE(bounds_caught);

  int index_caught = 0;
  try matrix.at(2, 0);
  catch %(bad-arg *detail): {
    index_caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"at");
  }
  EXPECT_TRUE(index_caught);
}

static void blis_mutations_fail_before_changing_destination(void) {
  BlisObject left = BlisObject.copy_rows(%((1.0 2.0) (3.0 4.0)), BLIS_DOUBLE);
  defer left.free();
  BlisObject wrong = BlisObject.copy_rows(%((1.0 2.0)), BLIS_DOUBLE);
  defer wrong.free();
  BlisObject destination = BlisObject.new(BLIS_DOUBLE, 2, 2);
  defer destination.free();
  destination.fill(7.0);

  int gemm_caught = 0;
  try destination.gemm(1.0, left, wrong, 0.0);
  catch %(bad-arg *detail): {
    gemm_caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"gemm");
  }
  EXPECT_TRUE(gemm_caught);
  EXPECT_NEAR(destination.at(0, 0), 7.0, 1e-12);

  BlisObject vector = BlisObject.copy_vector(%(1.0 2.0), BLIS_DOUBLE);
  defer vector.free();
  BlisObject short_vector = BlisObject.copy_vector(%(1.0), BLIS_DOUBLE);
  defer short_vector.free();
  int axpy_caught = 0;
  try vector.axpyv(1.0, short_vector);
  catch %(bad-arg *detail): {
    axpy_caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"axpyv");
  }
  EXPECT_TRUE(axpy_caught);
  EXPECT_NEAR(vector.at(0, 0), 1.0, 1e-12);

  BlisObject single = BlisObject.copy_vector(%(1.0 2.0), BLIS_FLOAT);
  defer single.free();
  int precision_caught = 0;
  try single.axpyv(1.0, vector);
  catch %(bad-types *detail): {
    precision_caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"axpyv");
  }
  EXPECT_TRUE(precision_caught);
  EXPECT_NEAR(single.at(0, 0), 1.0, 1e-12);
}

static void blis_scale_is_negation_with_a_parameter(void) {
  BlisObject matrix = BlisObject.copy_rows(
    %((1.0 -2.0) (3.0 4.0)), BLIS_DOUBLE
  );
  defer matrix.free();

  ScopeStats before = Scope.stats();
  Scope.retain();
  {
    defer Scope.release();
    BlisObject halved = matrix.scale(0.5);
    EXPECT_NEAR(halved.at(0, 0), 0.5, 1e-12);
    EXPECT_NEAR(halved.at(0, 1), -1.0, 1e-12);
    EXPECT_NEAR(halved.at(1, 1), 2.0, 1e-12);
    EXPECT_NEAR(matrix.at(1, 1), 4.0, 1e-12);

    BlisObject negated = -matrix;
    BlisObject scaled = matrix.scale(-1.0);
    for (int row = 0; row < matrix.rows(); row++)
      for (int column = 0; column < matrix.columns(); column++)
        EXPECT_NEAR(
          scaled.at(row, column), negated.at(row, column), 1e-12
        );

    BlisObject vector = BlisObject.copy_vector(%(3.0 4.0), BLIS_FLOAT);
    defer vector.free();
    EXPECT_NEAR(vector.scale(1.0 / vector.normfv()).normfv(), 1.0, 1e-6);
    EXPECT_NEAR(vector.normfv(), 5.0, 1e-6);
  }
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ((int) after.live_allocations, (int) before.live_allocations);

  BlisObject released = BlisObject.copy_vector(%(1.0), BLIS_DOUBLE);
  released.free();
  int state_caught = 0;
  try released.scale(2.0);
  catch %(bad-state *detail): {
    state_caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"scale");
  }
  EXPECT_TRUE(state_caught);
}

static void blis_bulk_read_agrees_with_element_reads(void) {
  BlisObject matrix = BlisObject.copy_rows(
    %((1.0 2.0 3.0) (4.0 5.0 6.0)), BLIS_DOUBLE
  );
  defer matrix.free();
  Scope.retain();
  defer Scope.release();

  Array rows = matrix.to_rows();
  EXPECT_INT_EQ((int) rows.len(), matrix.rows());
  for (int row = 0; row < matrix.rows(); row++) {
    Array values = rows[row];
    EXPECT_INT_EQ((int) values.len(), matrix.columns());
    for (int column = 0; column < matrix.columns(); column++)
      EXPECT_NEAR(values[column].double(), matrix.at(row, column), 1e-12);
  }
  BlisObject rows_copy = BlisObject.copy_rows(rows, BLIS_DOUBLE);
  defer rows_copy.free();
  EXPECT_NEAR(rows_copy.at(1, 2), 6.0, 1e-12);

  Array flipped = matrix.transpose_view().to_rows();
  EXPECT_INT_EQ((int) flipped.len(), 3);
  EXPECT_NEAR(flipped[2].array()[1].double(), 6.0, 1e-12);

  Array partial = matrix.part(0, 1, 2, 2).to_rows();
  EXPECT_NEAR(partial[0].array()[0].double(), 2.0, 1e-12);
  EXPECT_NEAR(partial[1].array()[1].double(), 6.0, 1e-12);

  Array column = matrix.column(-1).to_values();
  EXPECT_INT_EQ((int) column.len(), 2);
  EXPECT_NEAR(column[0].double(), 3.0, 1e-12);
  EXPECT_NEAR(column[1].double(), 6.0, 1e-12);
  BlisObject column_copy = BlisObject.copy_vector(column, BLIS_DOUBLE);
  defer column_copy.free();
  EXPECT_NEAR(column_copy.at(1, 0), 6.0, 1e-12);

  Array second = matrix.part(1, 0, 1, 3).to_values();
  EXPECT_INT_EQ((int) second.len(), 3);
  EXPECT_NEAR(second[0].double(), 4.0, 1e-12);
  EXPECT_NEAR(second[2].double(), 6.0, 1e-12);

  BlisObject single = BlisObject.copy_vector(%(0.5 0.25), BLIS_FLOAT);
  defer single.free();
  EXPECT_NEAR(single.to_values()[1].double(), 0.25, 1e-12);

  BlisObject empty = BlisObject.new(BLIS_DOUBLE, 0, 3);
  defer empty.free();
  EXPECT_INT_EQ((int) empty.to_rows().len(), 0);

  int vector_caught = 0;
  try matrix.to_values();
  catch %(bad-arg *detail): {
    vector_caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"to_values");
  }
  EXPECT_TRUE(vector_caught);
}

static void blis_operator_temporaries_are_bounded_per_iteration(void) {
  BlisObject matrix = BlisObject.copy_rows(
    %((0.75 0.25) (0.25 0.75)), BLIS_DOUBLE
  );
  defer matrix.free();
  BlisObject rank = BlisObject.copy_vector(%(0.5 0.5), BLIS_DOUBLE);
  defer rank.free();
  ScopeStats before = Scope.stats();

  for (int round = 0; round < 64; round++) {
    Scope.retain();
    {
      defer Scope.release();
      BlisObject next = matrix @ rank;
      rank.copy_from(next);
    }
    ScopeStats current = Scope.stats();
    EXPECT_INT_EQ(
      (int) current.live_allocations, (int) before.live_allocations
    );
  }
  EXPECT_NEAR(rank.at(0, 0), 0.5, 1e-12);
}

static void blis_lifecycle_and_version_are_exposed(void) {
  EXPECT_TRUE(Blis.version().len() > 0);
  Blis.shutdown();
  Blis.initialize();
}

void blis_suite(void) {
  $test.run(blis_application_path);
  $test.run(blis_views_alias_and_describe_owner_storage);
  $test.run(blis_owner_release_invalidates_views);
  $test.run(blis_collection_boundary_is_a_precision_copy);
  $test.run(blis_collection_copy_converts_every_numeric_tag);
  $test.run(blis_operators_are_scoped_blis_operations);
  $test.run(blis_scale_is_negation_with_a_parameter);
  $test.run(blis_bulk_read_agrees_with_element_reads);
  $test.run(blis_dimensions_empty_views_and_bounds);
  $test.run(blis_mutations_fail_before_changing_destination);
  $test.run(blis_operator_temporaries_are_bounded_per_iteration);
  $test.run(blis_lifecycle_and_version_are_exposed);
}

int main(void) {
  TestHarness_begin();
  $test.suite(blis_suite);
  return TestHarness_finish();
}
