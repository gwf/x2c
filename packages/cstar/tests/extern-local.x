/*  extern-local.x -- an external cell is not a fresh local allocation. */

#include "x2c.x"
#include "../src/cstar-macros.x"

int count = 0;

$cstar.verify("fact(0i == 0i)", "fact(__return == 1i)")
static int reset(void) {
  extern int count;
  count = 1;
  return count;
}
