#include "x2c.x"

int main(void) {
  int value = 1;
  macro Expression change() => (%!() => ++value)
  Func mutation = change();
  return 0;
}
