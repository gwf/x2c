#include "x2c.x"

int main(void) {
  Func f = %!() => puts("hi");
  (void) f;
  return 0;
}
