#include "x2c.x"

macro Expression $embed.missing() => (
  $(x2c.literal.string (x2c.embed.text "missing-embed-input.txt"))
)

String value = $embed.missing();
