#include "x2c.x"

int main(void) {
  List values = %(a b);
  List braced = %(head @{values} foot);
  List rejected = %(head @(values) foot);
  return rejected != braced;
}
