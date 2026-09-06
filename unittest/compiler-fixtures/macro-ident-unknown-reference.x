#include "x2c.x"

macro Expression $unknown_reference() => (
  $(x2c.ident "missing_generated_reference")
)

int value = $unknown_reference();
