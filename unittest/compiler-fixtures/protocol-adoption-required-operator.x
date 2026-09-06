#include "x2c.x"

typedef struct Vec {
  int value;
} *Vec;

static int equal_calls;

Var Vec.var(Vec value) {
  return Var.new(<vec>, value);
}

Vec Var.vec(Var value) {
  return (Vec) value.pointer();
}

int Vec.equal(Vec left, Vec right) {
  equal_calls += 1;
  return left.value == right.value;
}

int main(void) {
  Vec left = Scope.malloc(sizeof(struct Vec));
  Vec right = Scope.malloc(sizeof(struct Vec));
  left.value = 7;
  right.value = 7;
  printf("%d %d\n", left == right, equal_calls);
  return 0;
}
