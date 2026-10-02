#include "x2c.x"
#include "meta.x"

/* A macro pattern takes patterns in its holes, including another macro
   pattern. Inside a List pattern, `${$macro(...)}` is the macro's pattern;
   in the content of an `(expr TYPE ...)` shell it is the content, so the
   shell captures the expression's type. */
macro Expression $neg(Expr $v) => -$v;
macro Expression $add(Expr $a, Expr $b) => $a + $b;

meta static List classify(List e) {
  match (e) {
    case $add(?a, $neg(?b)): return x2c_literal_int(1);
    case %(expr ?type ${$add(?a, ?b)}):
      return x2c_literal_int(type.repr() == "(int)" ? 2 : 3);
    case %(!or ${$neg(%(expr ? (literal *)))}): return x2c_literal_int(4);
  }
  return x2c_literal_int(0);
}
macro Expression $kind(Expr $e) => $classify($e);

int main(void) {
  int x = 1, y = 2;
  double z = 1.5;
  printf("%d %d %d %d %d\n", $kind(x + -y), $kind(x + y), $kind(z + y),
         $kind(-7), $kind(x * y));
  return 0;
}
