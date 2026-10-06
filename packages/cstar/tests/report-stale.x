/*  report-stale.x -- inspecting the report cannot hide later obligations. */

#include "x2c.x"
#include "../src/cstar-macros.x"

$cstar.verify("fact(x <= 2147483647i)", "fact(__return == --x)")
static int negate(int x) {
  $cstar.helper(inspect_report);
  return -x;
}
