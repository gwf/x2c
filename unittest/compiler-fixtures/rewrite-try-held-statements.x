/* A statement in a try body that a try rule's replacement holds is offered
   to its own rules once, before the try rule runs, and not again when the
   replacement lowers. */

#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

static int tries = 0, raises = 0, switches = 0;

$rewrite($caught)
$rewrite($tried)
/* Each try is counted, then runs as written. */
meta Code count_try(Code node) {
  return $!{ { tries++; $node } };
}

$rewrite($raised)
/* Each raise is counted, then raised as written. */
meta Code count_raise(Code node) {
  return $!{ { raises++; $node } };
}

$rewrite($switched)
/* Each switch is counted, then runs as written. */
meta Code count_switch(Code node) {
  return $!{ { switches++; $node } };
}

static int pick(int n) {
  int r = 0;
  try {
    switch (n) {
      case 1: r = 10; break;
      default: r = 20;
    }
    if (n > 5) raise %(big);
  } catch %(big *): r += 100;
  finally { r++; }
  return r;
}

int main(void) {
  int small = pick(1), big = pick(9);
  printf("%d %d %d %d %d\n", small, big, tries, raises, switches);
  return 0;
}
