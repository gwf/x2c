#include "x2c.x"

int main(void) {
  const int target = 3; const int *pointer = &target;
  Var step = 1; pointer[0] += step;
  return 0;
}
