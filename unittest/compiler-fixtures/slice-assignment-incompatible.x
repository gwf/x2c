#include "x2c.x"

int main(void) {
  Array values = %[1, 2, 3];
  values[1:3] = %[8, 8];
  return 0;
}
