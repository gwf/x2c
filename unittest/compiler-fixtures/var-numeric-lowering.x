#include "x2c.x"
#include <math.h>

typedef Var Dynamic;
typedef Dynamic DynamicAlias;

typedef struct NumericBox {
  int value;
} NumericBox;

static int base_calls;
static int index_calls;
static int rhs_calls;
static int skipped_calls;

static int *pick_values(int *values) {
  base_calls++;
  return values;
}

static NumericBox *pick_box(NumericBox *box) {
  base_calls++;
  return box;
}

static int pick_index(void) {
  index_calls++;
  return 1;
}

static Var counted_rhs(int value) {
  rhs_calls++;
  return value;
}

static Var skipped_rhs(void) {
  skipped_calls++;
  return 1;
}

int main(void) {
  Dynamic a = 40;
  DynamicAlias b = 2;
  Var sum = a + b;
  Var product = a * b;
  Var shifted = a << b;
  Var bits = a | b;
  Var quotient = a / 4.0;
  double converted = sum;
  Var infinity = 1.0 / 0.0, not_number = 0.0 / 0.0;
  double converted_infinity = infinity;
  double converted_nan = not_number;
  double compound_infinity = 2.0;
  compound_infinity *= infinity;

  int native = 3;
  native += 4;
  int compound_result = (native += b);
  signed char signed_byte = 3;
  signed_byte += b;

  Var dynamic = 5;
  dynamic *= b;

  int values[] = {10, 20};
  pick_values(values)[pick_index()] += counted_rhs(3);
  NumericBox box = {7};
  pick_box(&box)->value *= counted_rhs(2);

  Var empty = (String) NULL;
  int logical = a && b;
  int short_and = empty && skipped_rhs();
  int short_or = a || skipped_rhs();
  int negated = !empty;
  int choice = empty ? 1 : 2;
  int branch = 0;
  if (a) branch++;

  Var loop = 2;
  while (loop) {
    branch++;
    loop -= 1;
  }

  Var for_cond = 0;
  for (for_cond = 2; for_cond; for_cond -= 1) branch++;

  Var do_cond = 0;
  do {
    branch++;
  } while (do_cond);

  int preserved = 1;
  NumericBox preserved_box = {2};
  int preserved_values[] = {3}, addressed = 4;
  NumericBox addressed_box = {5};
  try {
    preserved += b;
    preserved_box.value += b;
    preserved_values[0] += b;
    *(&addressed) += b;
    (&addressed_box)->value += b;
    raise %(invariant);
  }
  catch %(invariant): {
    branch++;
  }
  finally {
    branch++;
  }

  printf("ops=%ld,%ld,%ld,%ld,%.1f converted=%.1f\n",
         sum.long(), product.long(), shifted.long(), bits.long(),
         quotient.double(), converted);
  printf("compound=%d,%d,%d,%ld indexed=%d boxed=%d calls=%d,%d,%d\n",
         native, compound_result, signed_byte, dynamic.long(), values[1],
         box.value, base_calls, index_calls, rhs_calls);
  printf("truth=%d,%d,%d,%d,%d branch=%d preserved=%d skipped=%d\n",
         logical, short_and, short_or, negated, choice, branch, preserved,
         skipped_calls);
  printf("special=%d,%d,%d preserved-roots=%d,%d,%d,%d\n",
         isinf(converted_infinity), isnan(converted_nan),
         isinf(compound_infinity), preserved_box.value,
         preserved_values[0], addressed, addressed_box.value);
  return 0;
}
