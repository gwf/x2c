/* unbraced-invariant.x -- loop annotations in single-statement positions. */

#include "x2c.x"
$(import "../src/cstar.xmacro")

$cstar.verify("fact(0i <= x && x <= 100i)", "fact(__return == 0i)")
static int countdown(int x) {
  if (x > 0)
    $cstar.invariant("typeof(x, Tint) && 0i <= x && x <= 100i")
    while (x > 0) x--;
  else
    x = 0;
  return x;
}

$cstar.verify("fact(0i <= x && x <= 100i)", "fact(__return == 0i)")
static int countdown_sl(int x) {
  if (x > 0)
    $cstar.invariant_sl(
      "exists x_v. data_at x__addr Tint x_v ** "
      "fact(0i <= x_v && x_v <= 100i)")
    while (x > 0) x--;
  else
    x = 0;
  return x;
}

int main(void) {
  return countdown(3) || countdown(0) || countdown(-1) ||
         countdown_sl(3) || countdown_sl(0) || countdown_sl(-1);
}
