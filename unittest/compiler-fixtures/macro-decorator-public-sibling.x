#include "x2c.x"

/* A Unit decorator may add a public sibling beside its public target; the
   header declares both. */
macro Decorator $add_public(Unit $target) {
  $target
  int $x2c_ident("added_public");
}

$add_public()
int preserved_public = 42;
