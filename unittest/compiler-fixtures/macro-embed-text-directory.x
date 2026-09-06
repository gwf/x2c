#include "x2c.x"

macro Expression $embed.directory() => (
  $(x2c.literal.string (x2c.embed.text "macro-embed-text-definition"))
)

String value = $embed.directory();
