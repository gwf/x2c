#include "x2c.x"

macro Decorator $sneak(Unit $target) => {
  $(list $target
    `(declare (int)
      (bindings (bind ,(x2c.ident "sibling_one") ())))
    `(declare (int)
      (bindings (bind ,(x2c.ident "sibling_two") ()))))...
}

$sneak()
int visible_value = 42;
