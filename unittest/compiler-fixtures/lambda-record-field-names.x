#include "x2c.x"

/* The record a capturing lambda copies its captures into names its fields
   only as members, so a file-scope name that spells a field still binds. */
static Func add(int bias) {
  int value = bias;
  return %!(int v) => v + value;
}

static int c0(int x) => x + 1;

int main(void) {
  printf("%d %d\n", add(2)(3).int(), c0(4));
  return 0;
}
