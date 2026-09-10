/*  report-after.x -- later queries retain an earlier function's obligation. */

#include "x2c.x"
$(import "../src/cstar.xmacro")

$cstar.verify("fact(x <= 2147483647i)", "fact(__return == --x)")
static int negate(int x) {
  return -x;
}

$cstar.verify("fact(y <= 2147483647i)", "fact(__return == y + 0i)")
static int identity_value(int y) {
  $cstar.helper(inspect_report);
  return y;
}
