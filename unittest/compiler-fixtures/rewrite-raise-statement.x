#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

static int raised = 0;

$rewrite($raised)
/* A trace raise prints its detail count instead of recording an Error;
   any other raise is counted, then raised as written. */
meta Code count_raise(Code node) {
  match (node) {
    case $raised(%(expr ? (literal ? ? trace)), *details): {
      int count = details.len() / 2;
      return $!{ printf("trace %d\n", $count); };
    }
    case $raised(?, *): return $!{ { raised++; $node } };
  }
  return node;
}

static void report(int n) {
  raise %(trace (count $n) (twice ${n * 2}));
  if (n) raise %(counted (n $n) (text "raised"));
}

int main(void) {
  Error.initialize();
  Error.policy_set(<counted>, <collect>);
  int mark = Error.mark();
  report(0);
  report(3);
  List errors = Error.since(mark);
  List detail = errors.car().list().assoc(<detail>);
  printf("%s %d %d %s\n",
         errors.car().list().assoc(<code>).symbol().str(), raised,
         errors.len(), detail[1].list().cadr().string());
  return 0;
}
