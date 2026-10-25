#include "x2c.x"

macro Expression $embed.directory() =>
  $x2c_embed_text("macro-embed-text-definition");

String value = $embed.directory();
