#include "x2c.x"

macro Expression $derived(Expr $syntax) =>
  $Code.source_text($Code.type($syntax));

int value = $derived(1 + 2);
