#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

static int matched = 0;

$rewrite($matched)
/* A match on the literal `%(trace ...)` prints its arm count instead of
   matching; any other match is counted, then matched as written. */
meta Code count_match(Code node) {
  match (node) case $matched(?subject, *rows): {
    Var value = ((Code) subject).pattern_value();
    if (value is <list> && value.list().car() == <trace>) {
      int count = rows.len();
      return $!{ printf("trace %d\n", $count); };
    }
    return $!{ { matched++; $node } };
  }
  return node;
}

static int classify(List form) {
  match (form) {
    case %(add ?x ?y): return x.int() + y.int();
    case %(neg ?x): return -x.int();
    default: return 0;
  }
  return -1;
}

int main(void) {
  match (%(trace now)) {
    case %(a): printf("a\n");
    case %(b): printf("b\n");
    default: printf("never\n");
  }
  int sum = classify(%(add 1 2)) + classify(%(neg 4)) + classify(%(other));
  printf("%d matched %d\n", sum, matched);
  return 0;
}
