#include "x2c.x"

int main(void) {
  List values = %(1 2);
  values[0] += 1;
  return 0;
}
