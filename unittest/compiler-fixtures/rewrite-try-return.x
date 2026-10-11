/* A rule's replacement holds a try whose body returns. The returns the
   try holds convert to the function's declared result, as they do without
   the rule, and so does a return the replacement writes itself. */

#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

static int counted = 0, bail = 0, finished = 0;

$rewrite($caught)
$rewrite($tried)
/* Each try is counted, returns early while `bail` is set, then runs as
   written. */
meta Code count_try(Code node) {
  return $!{ { counted++; if (bail) return 40 + 2; $node } };
}

static int add(int x, int y) {
  try {
    return x + y;
  } finally { finished++; }
  return 0;
}

static int risky(int n) {
  if (n < 0) raise %(bad-arg);
  return n;
}

static Var twice(int n) {
  try {
    return risky(n) * 2;
  } catch %(bad-arg *): {
    return -1;
  } finally { finished++; }
  return 0;
}

int main(void) {
  int sum = add(1, 2);
  Var doubled = twice(4), failed = twice(-1);
  printf(
    "%d %d %d %d %d\n",
    sum, Var_int(doubled), Var_int(failed), counted, finished);
  bail = 1;
  int added = add(1, 2);
  Var early = twice(4);
  printf("%d %d %d %d\n", added, Var_int(early), counted, finished);
  return 0;
}
