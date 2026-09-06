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

protocol Var(Vec);

String Vec.str(Vec value) {
  (void) value;
  return %"owned";
}
