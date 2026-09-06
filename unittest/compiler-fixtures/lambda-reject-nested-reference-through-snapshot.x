#include "x2c.x"

int main(void) {
  int value = 1;
  Func outer = %!() => %!() using &value => ++value;
  return 0;
}
