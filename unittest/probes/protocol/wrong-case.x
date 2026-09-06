#include "x2c.x"

typedef struct Vec {
  int x;
} *Vec;

Var Vec.var(Vec value) {
  return Var.new(<vec>, value);
}

int main(void) {
  x2c_register_type(%"Vec");
  Vec value = Scope.malloc(sizeof(struct Vec));
  Var boxed = value;
  return boxed is <vec> ? 0 : 1;
}
