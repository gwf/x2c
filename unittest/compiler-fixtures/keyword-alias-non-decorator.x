#include "x2c.x"

macro Expression $fixture.value() => (42)

keyword value $fixture.value;

int main(void) {
  int value = 1;
  printf("%d %d\n", value(), value);
  return 0;
}
