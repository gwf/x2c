#include "x2c.x"

int main(void) {
  const int value = 1;
  Func f = %!() using &value => value = 5;
  (void) f;
  return 0;
}
