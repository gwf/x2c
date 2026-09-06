#include "x2c.x"

int main(void) {
  Array values = %[1];
  Var increment = 2;
  values[0] += increment;
  return 0;
}
