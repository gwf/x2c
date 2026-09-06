#include "x2c.x"

static void invalid(Array value) {
  raise %(invariant (value ($value)));
}

int main(void) {
  return 0;
}
