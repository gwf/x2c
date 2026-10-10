#include "x2c.x"

macro Unit $inspect(Type $type) {
  @(Type.fields $type)
}

$inspect(int);
