#include "x2c.x"

macro Expression $increment(Name $binding) => (%!() => ++$binding)

int main(void) {
  int value = 1;
  Func change = $increment(value);
  return 0;
}
