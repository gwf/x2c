#include "x2c.x"

int invalid_array(Var value) {
  return value is (int [4]);
}
