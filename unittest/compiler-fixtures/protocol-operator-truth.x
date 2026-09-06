#include "x2c.x"
#include <stdio.h>

typedef struct Vec {
  int x;
  int y;
} *Vec;

static int side_effects = 0;

Var Vec.var(Vec value) {
  return Var.new(<vec>, value);
}

Vec Var.vec(Var value) {
  return (Vec) value.pointer();
}

int Vec.truth(Vec value) {
  side_effects++;
  return value.x != 0 || value.y != 0;
}

protocol Var(Vec);

int main(void) {
  x2c_register_type(%"vec");
  Vec zero = Scope.malloc(sizeof(struct Vec));
  zero.x = 0;
  zero.y = 0;
  Vec one = Scope.malloc(sizeof(struct Vec));
  one.x = 1;
  one.y = 0;
  int result = zero && one;
  printf("%d %d\n", result, side_effects);
  side_effects = 0;
  int not_zero = !zero;
  int not_one = !one;
  int selected = zero ? 7 : 9;
  int disjunction = zero || one;
  return not_zero == 1 && not_one == 0 && selected == 9 &&
         disjunction == 1 && side_effects == 5 ? 0 : 1;
}
