#include "x2c.x"

int main(void) {
  Var value = 1, invalid = -value;
  return invalid.truthy();
}
