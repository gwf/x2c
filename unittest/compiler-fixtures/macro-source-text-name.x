#include "x2c.x"

macro Expression $named(Name $syntax) =>
  $Code.source_text($syntax);

String value = $named(identifier);
