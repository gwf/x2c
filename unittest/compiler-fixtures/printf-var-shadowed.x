#include "x2c.x"

static int printf(Var value) {
  return value.int();
}

int main(void) {
  Var value = 23;
  return printf(value) == 23 ? 0 : 1;
}
