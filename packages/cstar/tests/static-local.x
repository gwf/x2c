/*  static-local.x -- persistent storage cannot be verified as a fresh local. */

#include "x2c.x"
#include "../src/cstar-macros.x"

$cstar.verify("fact(0i == 0i)", "fact(__return == 1i)")
static int next(void) {
  static int count = 0;
  count++;
  return count;
}
