#include "x2c.x"
#include <stdio.h>

typedef struct Vec {
  int value;
} *Vec;

typedef Vec VecAlias;

Var Vec.var(Vec value) => Var.new(<vec>, value);
Vec Var.vec(Var value) => (Vec) value.pointer();

Vec Vec.new(int value) {
  Vec result = Scope.malloc(sizeof(struct Vec));
  result.value = value;
  return result;
}

int Vec.equal(Vec lhs, Vec rhs);

protocol Var(Vec);

// The member's own body compares natively; later callers still resolve it.
int Vec.equal(Vec lhs, Vec rhs) {
  VecAlias left = lhs, right = rhs;
  if (left == right) return 1;
  return lhs.value == rhs.value;
}

int main(void) {
  VecAlias a = Vec.new(1), b = Vec.new(1);
  int operator_equal = a == b;
  int method_equal = a.equal(b);
  printf("%d %d\n", operator_equal, method_equal);
  return 0;
}
