#include "x2c.x"

int main(void) {
  int number = 1, *pointer = &number;
  Var value = pointer;
  return value is pointer;
}
