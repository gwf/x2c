/*  parenthesized.x -- grouping preserves arithmetic meaning. */

#include "x2c.x"
$(import "../src/cstar.xmacro")

$cstar.verify("fact(0i <= x && x <= 10i)",
              "fact(__return == (x + 1i) * 2i)")
static int grouped(int x) {
  int result = 0;
  result = ((x + 1) * 2);
  return (result);
}
