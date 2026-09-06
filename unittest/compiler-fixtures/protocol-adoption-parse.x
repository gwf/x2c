#include "x2c.x"

typedef struct Vec {
  int x;
  int y;
} *Vec;

Var Vec.var(Vec v) {
  return Var.new(<vec>, v);
}

Vec Var.vec(Var v) {
  return (Vec) v.pointer();
}

String Vec.str(Vec v) {
  return %"Vec(${v.x},${v.y})";
}

protocol Var(Vec);

int main(void) {
  printf("ok\n");
  return 0;
}
