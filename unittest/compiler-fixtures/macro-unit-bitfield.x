#include "x2c.x"

meta static List bitfield_rows(void) {
  return %((declare (unsigned)
    (bindings
      (bind ${x2c_ident("ready")}
            ((bitfield (expr (int) (literal (int) "1"))))))));
}

macro Unit $bitfield() {
  @bitfield_rows()
}

$bitfield();
