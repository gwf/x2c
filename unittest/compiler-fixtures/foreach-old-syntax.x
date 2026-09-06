#include "x2c.x"

int main(void) {
  List values = %(1 2 3);
  for (int value in values) (void) value;
  return 0;
}
