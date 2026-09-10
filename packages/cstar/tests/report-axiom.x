/*  report-axiom.x -- a trust obligation prevents a verified result. */

#include "x2c.x"
$(import "../src/cstar.xmacro")

$cstar.verify("fact(x <= 2147483647i)", "fact(__return == x + 0i)")
static int identity_value(int x) {
  $cstar.helper(add_axiom);
  return x;
}
