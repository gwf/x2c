/*  parse-alias-enumerator.x -- an enumerator joins the scope around its
    enum, so it conflicts with an alias of that scope. An enum in an inner
    scope hides the alias, as any declaration there does.
*/
#include "x2c.x"

alias 5 as k;

static int inner(void) {
  enum { k };
  return k;
}

enum E { k };

int main(void) { return inner(); }
