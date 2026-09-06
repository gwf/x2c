#include "x2c.x"

static int macro(void) {
  return 42;
}

int main(void) {
  printf("%d\n", macro());
  return 0;
}
