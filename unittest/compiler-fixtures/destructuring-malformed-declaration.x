#include "x2c.x"

int main(void) {
  List values = %(1 2);
  Var (a,) = values;
  return 0;
}
