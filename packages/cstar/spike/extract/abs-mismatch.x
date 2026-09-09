/*  abs-mismatch.x -- abs.x with an outer decorator that rewrites the body
    after `$cstar.verify` recorded it.  The extractor must refuse it.
*/

#include "x2c.x"
#include "cstar-annotations.x"
$(import "cstar.xmacro")

#include <stdio.h>

macro Decorator $demo.append(Function $function) using $trace => {
  $(x2c.function.body $function)...
  int $trace = 0;
  (void) $trace;
}

static int nonnegative(int value) {
  return value >= 0;
}

$demo.append()
$cstar.verify("true", "result >= 0")
static int absolute(int x) {
  if (x < 0)
    return -x;
  else
    return x;
}

$cstar.verify("n >= 0", "result == 2 * n")
static int twice(int n) {
  int total = 0;
  int i = 0;
  $cstar.invariant("total == 2 * i")
  while (i < n) {
    total = total + 2;
    i = i + 1;
    $cstar.assert("total == 2 * (i)");
  }
  $cstar.proof(nonnegative, "total", "n");
  return total;
}

int main(void) {
  printf("%d %d %d\n", absolute(-7), absolute(7), twice(5));
  return 0;
}
