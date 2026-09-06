#include "x2c.x"

macro Decorator $add_public(Unit $target) => {
  $target
  int $(x2c.ident "unexpected_public");
}

$add_public()
int preserved_public = 42;
