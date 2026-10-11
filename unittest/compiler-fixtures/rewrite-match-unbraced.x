/* A match rule whose replacement holds the match itself reaches a nested
   match that is an unbraced body and uses an arm's binder, as it reaches
   one in a braced body. */

#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

static int matched = 0;

$rewrite($matched)
/* Each match is counted, then matched as written. */
meta Code count_match(Code node) {
  return $!{ { matched++; $node } };
}

/* The nested match is the arm's body. */
static int arm(List form) {
  match (form) {
    case %(pair ?inner):
      match (inner.list()) {
        case %(one): return 1;
      }
  }
  return 0;
}

/* The nested match is the body of the `if` that is the arm's body. */
static int arm_if(List form) {
  match (form) {
    case %(pair ?inner):
      if (inner is <list>)
        match (inner.list()) {
          case %(one): return 1;
        }
  }
  return 0;
}

/* The nested match is the body of a `while` in a braced arm. */
static int loop(List form) {
  int n = 0;
  match (form) {
    case %(pair ?inner): {
      while (n < 1)
        match (inner.list()) {
          case %(one): n = 5;
        }
    }
  }
  return n;
}

int main(void) {
  int a = arm(%(pair (one))), first = matched;
  int b = arm_if(%(pair (one))), second = matched;
  int w = loop(%(pair (one)));
  printf("%d %d %d %d %d %d\n", a, first, b, second, w, matched);
  return 0;
}
