#include "x2c.x"

macro Expression $embed.missing() =>
  $x2c_embed_text("missing-embed-input.txt");

String value = $embed.missing();
