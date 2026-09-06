#include "x2c.x"

macro Expression $slice(Expr $values) => (
  $values[1:]
)

int *values = $slice(values);
