#include "x2c.x"

static int identity(int macro) {
  return macro;
}

int main(void) {
  printf("%d\n", identity(42));
  return 0;
}
