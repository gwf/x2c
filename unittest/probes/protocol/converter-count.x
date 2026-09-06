#include "x2c.x"
#include <stdio.h>

typedef struct Vec {
  int x;
} *Vec;

static int box_count;

Var Vec.var(Vec value) {
  box_count++;
  return Var.new(<vec>, value);
}

int main(void) {
  x2c_register_type(%"vec");
  Vec value = Scope.malloc(sizeof(struct Vec));
  value.x = 7;
  Var boxed = value;
  printf("%d %d\n", box_count, boxed is <vec>);
  return 0;
}
