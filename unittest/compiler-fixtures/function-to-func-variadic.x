#include "x2c.x"

typedef int (*VariadicFunction)(int, ...);

static int sum(int count, ...) {
  return count;
}

int main(void) {
  VariadicFunction pointer = sum;
  Func function = pointer;
  return !function;
}
