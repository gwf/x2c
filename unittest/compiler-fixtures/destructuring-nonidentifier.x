#include "x2c.x"

int main(void) {
  List values = %(1 2);
  Var targets[] = {0, 0}, other;
  (targets[0], other) = values;
  return 0;
}
