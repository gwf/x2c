/* A Var subject that is not a List matches no List arm, not even the
   empty pattern or a rest binder, and reaches the `*` arm. A genuine
   empty List still matches the empty pattern. */

#include "x2c.x"

#include <stdio.h>

static const char *classify(Var subject) {
  match (subject) {
    case %(): return "empty";
    case %(pair ?a ?b): return "pair";
    case %(*rest): return "rest";
    default: return "other";
  }
  return "none";
}

static const char *strict(Var subject) {
  match (subject) {
    case %(): return "empty";
    case %(?head *tail): return "list";
  }
  return "none";
}

int main(void) {
  Var empty = %(), pair = %(pair 1 2), three = %(1 2 3);
  Var map = %{"k": 1}, text = "text", number = 7, nothing = void;
  printf("%s %s %s\n", classify(empty), classify(pair), classify(three));
  printf("%s %s %s %s\n", classify(map), classify(text), classify(number),
         classify(nothing));
  printf("%s %s %s %s\n", strict(empty), strict(three), strict(map),
         strict(number));
  return 0;
}
