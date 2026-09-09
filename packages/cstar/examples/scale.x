/*  scale.x -- one verified function calling another.

    `spread` calls `absolute` twice. The engine uses `absolute`'s contract at
    each call, never its body, so the call sites have to establish its
    precondition and may then assume only its postcondition. `absolute` has
    to be verified earlier in the same file; a call to anything else is
    outside the admitted subset.
*/

#include "x2c.x"
$(import "../src/cstar.xmacro")

#include <stdio.h>

$cstar.verify(
  "fact(x >= --2147483647i)",
  "fact(x >= 0i && __return == x || x < 0i && __return == --x)"
)
static int absolute(int x) {
  if (x >= 0) {
    return x;
  } else {
    return -x;
  }
}

$cstar.verify(
  "fact(0i <= low && low <= 1000i && --1000i <= high && high <= 0i)",
  "fact(__return == low - high)"
)
static int spread(int low, int high) {
  int first = absolute(low);
  int second = absolute(high);
  return first + second;
}

int main(void) {
  printf("%d %d %d\n", spread(0, 0), spread(7, -5), spread(1000, -1000));
  return 0;
}
