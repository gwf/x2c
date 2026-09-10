/*  test-ops.x -- twenty generated operator bindings from generated/xt_ops.h,
    against values computed by hand. Shapes, dtypes, optional arguments,
    tuple and list results, and a failing call are all covered.
*/

import "torch" with Torch, Tensor;

#include "test-support.x"
#include <math.h>

$(import "../../../unittest/test-macros.xmacro")

#define EXPECT_NEAR(actual, expected, tolerance) \
  EXPECT_TRUE(fabs((actual) - (expected)) < (tolerance))

/* [[1 2 3] [4 5 6]] as float64. */
static Tensor _grid(void) =>
  Tensor.of(%((1 2 3) (4 5 6)), %(2 3), XT_FLOAT64);

static void ops_elementwise(void) {
  $test.scoped();
  Tensor a = _grid();

  // softmax along the rows: 1 / (1 + e + e^2) is the first entry.
  Tensor soft = a.softmax(1);
  EXPECT_NEAR(soft.to_values()[0].double(), 0.09003057317038046, 1e-12);
  EXPECT_NEAR(soft.sum().item().double(), 2.0, 1e-12);

  // cumsum along the rows: [[1 3 6] [4 9 15]].
  Tensor running = a.cumsum(1, -1);
  EXPECT_NEAR(running.to_values()[2].double(), 6.0, 1e-12);
  EXPECT_NEAR(running.to_values()[5].double(), 15.0, 1e-12);

  // clamp with two present Scalars: [[2 2 3] [4 5 5]].
  Tensor held = a.clamp(2, 5);
  EXPECT_NEAR(held.sum().item().double(), 21.0, 1e-12);

  // clamp with an absent upper bound: [[2 2 3] [4 5 6]].
  Tensor floored = a.clamp(2, Var.null());
  EXPECT_NEAR(floored.sum().item().double(), 22.0, 1e-12);

  // A floating Scalar keeps its kind across the ABI.
  EXPECT_NEAR(a.clamp(Var.null(), 2.5).sum().item().double(), 13.0, 1e-12);

  EXPECT_NEAR(a.maximum(a.flip(%(1))).sum().item().double(), 3.0 + 2 + 3 + 6 + 5 + 6,
              1e-12);
  EXPECT_NEAR(a.flip(%(1)).to_values()[0].double(), 3.0, 1e-12);
}

static void ops_reductions(void) {
  $test.scoped();
  Tensor a = _grid();

  // argmax over the rows is [2 2]; the absent dim reduces everything.
  EXPECT_NEAR(a.argmax(1, 1).sum().item().double(), 4.0, 1e-12);
  EXPECT_NEAR(a.reshape(%(6)).argmax(0, 0).item().double(), 5.0, 1e-12);

  // amax over the rows is [3 6].
  EXPECT_NEAR(a.amax(%(1), 0).sum().item().double(), 9.0, 1e-12);

  // prod of every element, with and without an explicit result dtype.
  EXPECT_NEAR(a.prod(-1).item().double(), 720.0, 1e-12);
  EXPECT_INT_EQ(a.prod(XT_FLOAT32).dtype(), XT_FLOAT32);
  EXPECT_INT_EQ(a.cumsum(1, XT_INT64).dtype(), XT_INT64);

  // logsumexp of [1 2 3] is 3 + log(1 + e^-1 + e^-2).
  EXPECT_NEAR(a.logsumexp(%(1), 0).to_values()[0].double(),
              3.4076059644443806, 1e-12);
  EXPECT_NEAR(a.narrow(1, 0, 2).sum().item().double(), 12.0, 1e-12);
}

static void ops_tuple_and_list_results(void) {
  $test.scoped();
  Tensor a = _grid();

  // topk returns (values, indices): [[3 2] [6 5]] and [[2 1] [2 1]].
  List best = a.topk(2, 1, 1, 1);
  EXPECT_INT_EQ(best.len(), 2);
  Tensor values = best[0].tensor(), positions = best[1].tensor();
  EXPECT_STR_EQ(values.shape().str(), "( 2 2 )");
  EXPECT_NEAR(values.sum().item().double(), 16.0, 1e-12);
  EXPECT_NEAR(positions.to_dtype(XT_FLOAT64).sum().item().double(), 6.0, 1e-12);

  // sort descending puts 3 first in the top row.
  List ordered = a.sort(1, 1);
  EXPECT_NEAR(ordered[0].tensor().to_values()[0].double(), 3.0, 1e-12);

  // split by rows returns two 1x3 tensors.
  List rows = a.split(1, 0);
  EXPECT_INT_EQ(rows.len(), 2);
  EXPECT_STR_EQ(rows[0].tensor().shape().str(), "( 1 3 )");
  EXPECT_NEAR(rows[1].tensor().sum().item().double(), 15.0, 1e-12);

  // chunk into three columns.
  List columns = a.chunk(3, 1);
  EXPECT_INT_EQ(columns.len(), 3);
  EXPECT_NEAR(columns[2].tensor().sum().item().double(), 9.0, 1e-12);
}

static void ops_list_and_creation_arguments(void) {
  $test.scoped();
  Tensor a = _grid();

  // cat and stack take a List of tensors.
  Tensor doubled = Tensor.cat(%($a $a), 0);
  EXPECT_STR_EQ(doubled.shape().str(), "( 4 3 )");
  EXPECT_NEAR(doubled.sum().item().double(), 42.0, 1e-12);
  Tensor stacked = Tensor.stack(%($a $a), 0);
  EXPECT_STR_EQ(stacked.shape().str(), "( 2 2 3 )");

  // linspace is a creation op: [0 0.25 0.5 0.75 1].
  Tensor ramp = Torch.linspace(0, 1, 5, XT_FLOAT64, NULL);
  EXPECT_NEAR(ramp.to_values()[1].double(), 0.25, 1e-12);
  EXPECT_NEAR(ramp.sum().item().double(), 2.5, 1e-12);
  EXPECT_INT_EQ(Torch.linspace(0, 1, 5, XT_FLOAT32, NULL).dtype(),
                XT_FLOAT32);

  // eye and tril work on their own.
  EXPECT_NEAR(Torch.eye(3, XT_FLOAT64, NULL).sum().item().double(), 3.0, 1e-12);
  EXPECT_NEAR(Torch.eye(3, XT_FLOAT64, NULL).tril(0).sum().item().double(), 3.0,
              1e-12);
}

static void ops_masks_and_errors(void) {
  $test.scoped();
  Tensor a = _grid();
  Tensor mask = a.gt(3);
  EXPECT_INT_EQ(mask.dtype(), XT_BOOL);

  // where keeps the masked entries and zeroes the rest.
  Tensor kept = mask.where(a, Tensor.zeros(%(2 3), XT_FLOAT64));
  EXPECT_NEAR(kept.sum().item().double(), 15.0, 1e-12);
  EXPECT_NEAR(a.masked_select(mask).sum().item().double(), 15.0, 1e-12);
  EXPECT_INT_EQ(a.masked_select(mask).numel(), 3);

  // A shape libtorch rejects raises through the same <bad-state> as the
  // hand-written operations, and the error text survives.
  int caught = 0;
  try {
    (void) a.mm(a);
  }
  catch %(bad-state *): caught++;
  EXPECT_INT_EQ(caught, 1);

  // A Scalar argument that is neither integer nor floating is refused.
  try {
    (void) a.clamp("two", 5);
  }
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 2);
}

static void ops_lifetimes(void) {
  $test.scoped();
  ScopeStats before = Scope.stats();
  {
    Scope.retain();
    defer Scope.release();
    Tensor a = _grid();
    for (int i = 0; i < 50; i++) {
      List rows = a.split(1, 0);
      (void) rows[0].tensor().softmax(1).sum();
    }
  }
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
}

void torch_ops_suite(void) {
  $test.run(ops_elementwise);
  $test.run(ops_reductions);
  $test.run(ops_tuple_and_list_results);
  $test.run(ops_list_and_creation_arguments);
  $test.run(ops_masks_and_errors);
  $test.run(ops_lifetimes);
}

int main(void) {
  TestHarness_begin();
  $test.suite(torch_ops_suite);
  return TestHarness_finish();
}
