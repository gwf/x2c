#include "x2c.x"

int invalid_unknown(Var value) {
  return value is UnknownType;
}
