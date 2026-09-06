#include "x2c.x"

typedef struct Vec {
  int x;
} *Vec;

Var Vec.var(Vec value) {
  return Var.new(<vec>, value);
}
