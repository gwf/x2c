#include "x2c.x"

static int increment(int &value) => ++value;

int main(void) {
  int value = 1;
  Func change = %!() => increment(value);
  return 0;
}
