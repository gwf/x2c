#include "x2c.x"

static int sum(int count, ...) {
  return count;
}

int main(void) {
  Func function = sum;
  return !function;
}
