#include "x2c.x"

macro Expression $twice($value) => ($value + $value)

int main(void) {
  int value = 21;
  printf("%d\n", $twice(value));
  return 0;
}
