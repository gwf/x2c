#include "x2c.x"

import "geo";

int package_type_is(Var value) {
  return value is geo.Vec;
}
