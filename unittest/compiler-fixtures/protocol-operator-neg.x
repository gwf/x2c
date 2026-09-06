#include "x2c.x"
#include <stdio.h>

typedef struct Vec {
  int value;
} *Vec;

static int neg_calls = 0;

Var Vec.var(Vec value) {
  return Var.new(<vec>, value);
}

Vec Var.vec(Var value) {
  return (Vec) value.pointer();
}

Vec Vec.neg(Vec value) {
  neg_calls++;
  Vec result = Scope.malloc(sizeof(struct Vec));
  result.value = -value.value;
  return result;
}

protocol Var(Vec);

int main(void) {
  Vec value = Scope.malloc(sizeof(struct Vec));
  value.value = 7;
  Vec result = -value;
  printf("%d %d\n", result.value, neg_calls);
  return 0;
}
