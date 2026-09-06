#include "x2c.x"

typedef struct Vec {
  int x;
} *Vec;

Var Vec.var(Vec value) {
  return Var.new(<vec>, value);
}

Vec Var.vec(Var value) {
  return (Vec) value.pointer();
}

String Vec.str(Vec value) {
  return %"${value.x}";
}

int main(void) {
  Vec left = Scope.malloc(sizeof(struct Vec));
  Vec right = Scope.malloc(sizeof(struct Vec));
  Vec sum = left + right;
  return sum.x;
}
