#include "x2c.x"

macro Unit $bitfield() => {
  $(list
    `(declare (unsigned)
      (bindings
        (bind ,(x2c.ident "ready")
              ((bitfield (expr (int) (literal (int) "1"))))))))...
}

$bitfield();
