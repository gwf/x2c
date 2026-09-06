#include "x2c.x"

static int increment(int value) {
  return value + 1;
}

macro Unit $define_body_callers(Expr $callable) => {
  static int $(x2c.ident "macro_body_parens")(int parens_value) {
    return ($callable)(parens_value);
  }

  static int $(x2c.ident "macro_body_direct")(int direct_value) {
    return $callable(direct_value);
  }
}

macro Expression $call_parenthesized(Expr $callable, Expr $value) => (
  ($callable)($value)
)

$define_body_callers(increment);

static int ordinary_parens(int value) {
  return (increment)(value);
}

int main(void) {
  printf("%d %d %d %d\n",
         macro_body_parens(41),
         macro_body_direct(41),
         ordinary_parens(41),
         $call_parenthesized(increment, 41));
  return 0;
}
