#include "x2c.x"

typedef struct Vec {
  int x;
  int y;
} *Vec;

Var Vec.var(Vec value) {
  return Var.new(<vec>, value);
}

Vec Var.vec(Var value) {
  return (Vec) value.pointer();
}

String Vec.str(Vec value) {
  return %"Vec(${value.x},${value.y})";
}

protocol Var(Vec);

int main(void) {
  Vec value = Scope.malloc(sizeof(struct Vec));
  value.x = 1;
  value.y = 2;
  Var boxed = value;
  printf("%s\n", boxed.str());
  return 0;
}
