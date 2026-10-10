#include "x2c.x"

macro Expression $spelling(Expr $value) =>
  $(Code.binding_spelling $value);

int value = $spelling(40 + 2);
