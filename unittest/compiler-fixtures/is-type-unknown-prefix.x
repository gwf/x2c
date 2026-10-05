#include "x2c.x"

int invalid_prefix(Var value) {
  return value is uint64_trick;
}
