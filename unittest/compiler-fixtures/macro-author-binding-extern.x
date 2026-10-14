/* A template that keeps a file-scope name does not rename block-scope
   `extern` declarations or function prototypes of that spelling: they name
   the external symbol, so only the shadowing locals get a fresh spelling. */

#include "x2c.x"

#include <stdio.h>

int leaked = 100;
int helper(void) { return 7; }

macro Expression $leaked() => leaked;
macro Expression $helped() => helper();

static int use_extern(void) {
  extern int leaked;
  leaked += 1;
  return leaked;
}

static int local_proto(void) {
  int helper(void);
  return helper();
}

static int shadow(void) {
  int leaked = 5;
  int helper = 3;
  return $leaked() + leaked + $helped() + helper;
}

int main(void) {
  printf("%d %d %d %d\n", use_extern(), local_proto(), shadow(), leaked);
  return 0;
}
