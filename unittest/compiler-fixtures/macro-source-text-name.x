#include "x2c.x"

macro Expression $named(Name $syntax) => (
  $(x2c.literal.string (x2c.source.text $syntax))
)

String value = $named(identifier);
