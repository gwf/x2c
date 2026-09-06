#include "x2c.x"
#include <stdio.h>

typedef struct Vec {
  int value;
} *Vec;

static int rhs_evals = 0;

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

Vec int.vec(int value) {
  return Vec.new(value);
}

Vec Vec.add(Vec lhs, Vec rhs) {
  return Vec.new(lhs.value + rhs.value);
}

protocol Var(Vec);

static Vec pick_rhs(Vec value) {
  rhs_evals++;
  return value;
}

int main(void) {
  Vec value = Vec.new(2);
  Vec rhs = Vec.new(3);
  Vec compound = (value += pick_rhs(rhs));
  Vec prefix = ++value;
  Vec postfix = value++;
  Vec try_old = NULL;
  try {
    value += rhs;
    try_old = value++;
  }
  catch %(invariant): {}
  printf(
    "%d %d %d %d %d %d\n",
    compound.value, prefix.value, postfix.value,
    value.value, try_old.value, rhs_evals
  );
  return 0;
}
