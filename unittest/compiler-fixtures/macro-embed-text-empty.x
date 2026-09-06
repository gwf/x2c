#include "x2c.x"

macro Expression $embed.empty_path() => (
  $(x2c.literal.string (x2c.embed.text ""))
)

String value = $embed.empty_path();
