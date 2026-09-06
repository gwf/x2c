#include "x2c.x"

macro Expression $derived(Expr $syntax) => (
  $(x2c.literal.string
    (x2c.source.text (x2c.syntax.type $syntax)))
)

int value = $derived(1 + 2);
