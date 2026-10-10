#include "x2c.x"

macro Expression $named(Name $syntax) =>
  $(x2c.literal.string (Code.source_text $syntax));

String value = $named(identifier);
