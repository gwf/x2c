#include "x2c.x"

macro Expression $forged() => (
  $(x2c.expr.ident '(binding 999 "missing"))
)

int value = $forged();
