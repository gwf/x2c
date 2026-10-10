#include "x2c.x"

macro Expression $derived(Expr $syntax) =>
  $(x2c.literal.string
    (Code.source_text (Code.type $syntax)));

int value = $derived(1 + 2);
