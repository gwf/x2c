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

/* A nested pattern keeps the macro's operator, and the compiler's private
   binders do not collide with an argument binder of the same spelling. */
macro Expression $mul(Expr $a, Expr $b) => $a * $b;
static int literal_product(List e) {
  match (e) case $mul(?a, %(expr ? (literal *))): return 1;
  return 0;
}
static int literal_sum(List e) {
  match (e) case $add(?__pattern_0, %(expr ? (literal *))): return 1;
  return 0;
}

/* A bare `*` in a sequence hole matches any number of arguments. */
macro Expression $call(Expr $callee, Expr $arguments...) =>
  $callee($arguments...);
static int any_call(List e) {
  match (e) case $call(%(expr ? (ident "f")), *): return 1;
  return 0;
}

int main(void) {
  int x = 1, y = 2;
  double z = 1.5;
  printf("%d %d %d %d %d\n", $kind(x + -y), $kind(x + y), $kind(z + y),
         $kind(-7), $kind(x * y));
  List plus = %(expr (int) (op + (expr (int) (ident "x"))
                               (expr (int) (literal (int) "7"))));
  List times = %(expr (int) (op * (expr (int) (ident "x"))
                                (expr (int) (literal (int) "7"))));
  printf("%d %d %d\n", literal_product(plus), literal_product(times),
         literal_sum(plus));
  List f = %(expr () (ident "f"));
  printf("%d %d\n", any_call(%(expr (int) (call $f (args)))),
         any_call(%(expr (int) (call $f (args $plus $times)))));
  return 0;
}
