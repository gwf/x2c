/*  static-local.x -- persistent storage cannot be verified as a fresh local. */

#include "x2c.x"
$(import "../src/cstar.xmacro")

$cstar.verify("fact(0i == 0i)", "fact(__return == 1i)")
static int next(void) {
  static int count = 0;
  count++;
  return count;
}
