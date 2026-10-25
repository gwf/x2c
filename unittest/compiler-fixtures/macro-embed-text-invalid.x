#include "x2c.x"

macro Expression $embed.invalid(Literal $path) =>
  $x2c_embed_text($path);

String value = $embed.invalid(123);
