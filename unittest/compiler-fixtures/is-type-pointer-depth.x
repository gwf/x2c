#include "x2c.x"

int invalid_pointer_depth(Var value) {
  return value is (int ***);
}
