/*  abs-unbounded.x -- absolute value without the INT_MIN exclusion.

    The contract excludes INT_MIN, whose negation overflows.
    `abs-unbounded.x` is the same program without that exclusion; its
    obligation is what cstar-verify reports.
*/

#include "x2c.x"
$(import "../src/cstar.xmacro")

#include <stdio.h>

$cstar.verify(
  "fact(x <= 2147483647i)",
  "fact(x >= 0i && __return == x || x < 0i && __return == --x)"
)
static int absolute(int x) {
  if (x >= 0) {
    return x;
  } else {
    return -x;
  }
}

int main(void) {
  printf("%d %d %d\n", absolute(-7), absolute(0), absolute(7));
  return 0;
}
