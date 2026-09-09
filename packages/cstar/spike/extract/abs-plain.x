/*  abs-plain.x -- the same program without annotations.

    Compiles and runs exactly as it would without the annotations; the
    contracts live only in the compile-time Lisp session.
*/

#include "x2c.x"

#include <stdio.h>

static int nonnegative(int value) {
  return value >= 0;
}

static int absolute(int x) {
  if (x < 0)
    return -x;
  else
    return x;
}

static int twice(int n) {
  int total = 0;
  int i = 0;
  while (i < n) {
    total = total + 2;
    i = i + 1;
  }
  return total;
}

int main(void) {
  printf("%d %d %d\n", absolute(-7), absolute(7), twice(5));
  return 0;
}
