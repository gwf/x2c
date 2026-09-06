#include "x2c.x"

int invalid_pointer_spelling(Var value) {
  return value is int *;
}
