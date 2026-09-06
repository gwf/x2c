#include "x2c.x"

static void invalid(Map value) {
  raise %(invariant (value $value));
}

int main(void) {
  return 0;
}
