/*  unsupported.x -- a construct outside the admitted subset. The plan
    excludes `defer`, and cstar-verify must say so with its location.
*/

#include "x2c.x"
$(import "../src/cstar.xmacro")

#include <stdio.h>

$cstar.verify("fact(true)", "fact(true)")
static int deferred(int x) {
  defer printf("%d\n", x);
  return x;
}
