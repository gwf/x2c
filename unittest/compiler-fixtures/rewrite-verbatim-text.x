#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

static int counted = 0;

$rewrite($matched)
/* A match with only a default arm is counted and runs its body, in C text
   that holds the subject and the body. The transform lowers both inside
   the text, and the cleanup walk runs the body's exits. Any other match is
   left to the compiler. */
meta Code counted_default(Code node) {
  match (node) case $matched(?subject, *rows): {
    List (pattern, body) = rows.car();
    if (rows.len() == 1 && pattern.car() == <*>)
      return Code.lowered(
        %(block ("counted++; (void) (" $subject "); {" $body "}")));
  }
  return node;
}

static int pick(Var v) {
  defer printf("left pick\n");
  match (%(seen ${v + 1})) {
    default: {
      defer printf("left default\n");
      String text = %"default for ${v}";
      printf("%s\n", text);
      return 2;
    }
  }
  return 0;
}

static int other(List form) {
  match (form) {
    case %(one): return 1;
    default: return 0;
  }
  return -1;
}

int main(void) {
  int picked = pick(1), one = other(%(one));
  printf("%d %d counted %d\n", picked, one, counted);
  return 0;
}
