/* A return in a match that a rule's replacement holds converts to the
   function's declared result, as it does without the rule. */

#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

static int matched = 0;

$rewrite($matched)
/* Each match is counted, then matched as written. */
meta Code count_match(Code node) {
  return $!{ { matched++; $node } };
}

static Var add(List form) {
  match (form) {
    case %(add ?x ?y): return Var_int(x) + Var_int(y);
  }
  return 0;
}

int main(void) {
  Var sum = add(%(add 1 2)), none = add(%(other));
  printf("%d %d %d\n", Var_int(sum), Var_int(none), matched);
  return 0;
}
