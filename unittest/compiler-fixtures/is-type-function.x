#include "x2c.x"

int invalid_function(Var value) {
  return value is (int (int));
}
