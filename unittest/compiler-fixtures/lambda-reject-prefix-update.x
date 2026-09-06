#include "x2c.x"

int main(void) {
  int value = 1;
  Func change = %!() => ++value;
  return 0;
}
