#include "x2c.x"

/* String `+` and `+=` lower through the `add` row of protocol Var(String):
   a binding-head String_add call, a generated update helper, and a cached
   constant when both operands are literals. */

static String suffix(void) {
  return %"!";
}

int main(void) {
  Scope.retain();
  String left = %"con", right = %"cat";
  String joined = left + right;
  String mixed = left + "raw";
  String constant = %"folded " + "pair";
  joined += suffix();
  printf("%s %s %s\n", joined, mixed, constant);
  Scope.release();
  return 0;
}
