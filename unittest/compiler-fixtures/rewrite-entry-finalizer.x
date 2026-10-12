/* A defer finalizer runs as a callback of its own, so a rule inside it
   has no source function entry to place at. */

#include "x2c.x"
#include "rewrite.x"
#include "meta.x"

#include <stdio.h>

static int tally(int step) => step;

macro Expression $tallied(Expr $step) => tally($step);

$rewrite($tallied)
meta Code count_tally(Code code) {
  x2c_place(%(function-entry), $!{ printf("enter\n"); });
  return code;
}

static int callable(int n) {
  {
    defer printf("finalizer %d\n", tally(n));
    printf("block\n");
  }
  return n;
}

int main(void) {
  return callable(1);
}
