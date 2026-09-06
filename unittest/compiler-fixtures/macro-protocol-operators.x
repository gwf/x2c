#include "x2c.x"
#include <stdio.h>

typedef struct Vec {
  int value;
} *Vec;

static int add_calls = 0;
static int neg_calls = 0;
static int equal_calls = 0;
static int compare_calls = 0;

Var Vec.var(Vec value) {
  return Var.new(<vec>, value);
}

Vec Var.vec(Var value) {
  return (Vec) value.pointer();
}

Vec Vec.new(int value) {
  Vec result = Scope.malloc(sizeof(struct Vec));
  result.value = value;
  return result;
}

Vec Vec.add(Vec lhs, Vec rhs) {
  add_calls++;
  return Vec.new(lhs.value + rhs.value);
}

Vec Vec.neg(Vec value) {
  neg_calls++;
  return Vec.new(-value.value);
}

int Vec.equal(Vec lhs, Vec rhs) {
  equal_calls++;
  return lhs.value == rhs.value;
}

int Vec.compare(Vec lhs, Vec rhs) {
  compare_calls++;
  return lhs.value - rhs.value;
}

protocol Var(Vec);

int report(
  Vec sum, Vec negated, int equal, int unequal, int less, int contains) {
  printf(
    "%d %d %d %d %d %d %d %d %d %d\n",
    sum.value, negated.value, equal, unequal, less, contains,
    add_calls, neg_calls, equal_calls, compare_calls
  );
  return 0;
}

macro Expression $report_ops(Expr $lhs, Expr $rhs, Expr $values) => (
  report(
    $lhs + $rhs,
    -$lhs,
    $lhs == $rhs,
    $lhs != $rhs,
    $lhs < $rhs,
    2 in $values
  )
)

int main(void) {
  Vec lhs = Vec.new(2), rhs = Vec.new(5);
  Array values = %[1, 2, 3];
  return $report_ops(lhs, rhs, values);
}
