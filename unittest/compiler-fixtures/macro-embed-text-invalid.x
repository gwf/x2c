#include "x2c.x"

macro Expression $embed.invalid(Literal $path) => (
  $(x2c.literal.string (x2c.embed.text $path))
)

String value = $embed.invalid(123);
