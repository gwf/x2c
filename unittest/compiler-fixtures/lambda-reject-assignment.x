#include "x2c.x"

int main(void) {
  int value = 1;
  Func change = %!() => value = 2;
  return 0;
}
