#include "x2c.x"

int main(void) {
  int value = 1;
  Func address = %!() => &value;
  return 0;
}
