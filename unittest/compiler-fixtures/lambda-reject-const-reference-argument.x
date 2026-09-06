#include "x2c.x"

static int increment(int &value) => ++value;

int main(void) {
  const int value = 1;
  Func change = %!() using &value => increment(value);
  return 0;
}
