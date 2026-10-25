#include "x2c.x"

macro Expression $unknown_reference() =>
  $x2c_ident("missing_generated_reference");

int value = $unknown_reference();
