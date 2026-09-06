#include "x2c.x"
#include <stdio.h>

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

Vec Vec.add(Vec a, Vec b) {
  Vec result = Scope.malloc(sizeof(struct Vec));
  result.x = a.x + b.x;
  result.y = a.y + b.y;
  return result;
}

int Vec.compare(Vec a, Vec b) {
  return a.x == b.x ? a.y - b.y : a.x - b.x;
}

protocol Var(Vec);

int main(void) {
  x2c_register_type(%"vec");
  Vec a = Scope.malloc(sizeof(struct Vec));
  a.x = 1;
  a.y = 2;
  Vec b = Scope.malloc(sizeof(struct Vec));
  b.x = 10;
  b.y = 20;
  Vec c = a + b;
  printf("%d %d %d %d\n", c.x, c.y, a < b, b < a);
  return 0;
}
