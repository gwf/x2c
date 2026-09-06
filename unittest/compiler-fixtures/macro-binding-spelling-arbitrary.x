#include "x2c.x"

macro Expression $spelling(Expr $value) => (
  $(x2c.binding.spelling $value)
)

int value = $spelling(40 + 2);
