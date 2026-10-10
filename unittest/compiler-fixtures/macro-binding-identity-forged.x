#include "x2c.x"

macro Expression $forged() =>
  $(begin '(expr () (ident (binding 999 "missing"))));

int value = $forged();
