/* A switch rule sees the switches the source writes, those in a match's
   arms included, but not the switch the match lowers to. */

#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

static int counted = 0;

macro Stmt $any_switch(Expr $subject, Stmt $body) { switch ($subject) $body }

$rewrite($any_switch)
/* Each switch is counted, then switches as written. */
meta Code count_switch(Code node) {
  match (node) case %(switch *): return $!{ { counted++; $node } };
  return node;
}

static int pick(int n) {
  switch (n) {
    case 1: return 10;
  }
  return 0;
}

static int arm(List form, int n) {
  match (form) {
    case %(pick): {
      switch (n) {
        case 2: return 20;
      }
      return 21;
    }
    default: return 0;
  }
  return -1;
}

int main(void) {
  int one = pick(1), first = counted;
  int two = arm(%(pick), 2), second = counted;
  int other = arm(%(other), 2);
  printf("%d %d %d %d %d %d\n", one, first, two, second, other, counted);
  return 0;
}
