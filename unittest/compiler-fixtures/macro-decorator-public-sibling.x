#include "x2c.x"

/* The language reference says a public target cannot gain new public
   siblings. The compiler does not enforce that rule yet, so this records the
   current interface; unittest/STATUS.md tracks the gap. */
macro Decorator $add_public(Unit $target) {
  $target
  int $x2c_ident("unexpected_public");
}

$add_public()
int preserved_public = 42;
