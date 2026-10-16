/* A template that keeps a file-scope name with `using` does not rename
   block-scope `extern` declarations or function prototypes of that
   spelling: they name the external symbol, so only the shadowing locals get
   a fresh spelling. */

#include "x2c.x"

#include <stdio.h>

int leaked = 100;
int helper(void) { return 7; }

macro Expression $leaked() using leaked => leaked;
macro Expression $helped() using helper => helper();

static int use_extern(void) {
  extern int leaked;
  leaked = $leaked() + 1;
  return leaked;
}

static int local_proto(void) {
  int helper(void);
  return $helped();
}

static int shadow(void) {
  int leaked = 5;
  int helper = 3;
  return $leaked() + leaked + $helped() + helper;
}

int main(void) {
  int bumped = use_extern(), proto = local_proto(), shadowed = shadow();
  printf("%d %d %d %d\n", bumped, proto, shadowed, leaked);
  return 0;
}
