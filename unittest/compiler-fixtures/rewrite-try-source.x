/* A try rule whose replacement holds the try itself applies once to each
   try, a nested one included. */

#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

static int counted = 0;

$rewrite($tried)
/* Each try with a finalizer is counted, then runs as written. */
meta Code count_try(Code node) {
  return $!{ { counted++; $node } };
}

static int run(int n) {
  int r = 0;
  try {
    r = n;
    try { r *= 2; } finally { r++; }
  } finally { r++; }
  return r;
}

int main(void) {
  int r = run(3);
  printf("%d %d\n", r, counted);
  return 0;
}
