#include "x2c.x"

typedef struct Point { int x; int y; } Point;

// An Expression macro's result is one operand at its call site, whether the
// body was written in the definition or built by compile-time Lisp. Neither
// producer records grouping: emission parenthesizes from C precedence.
macro Expression $twice($value) => $value + $value;

macro Expression $wider(Expr $value) => $value + 1;

$(defun sum-expr (a b) `(expr () (op + ,a ,b)))

macro Expression $lispsum(Expr $a, Expr $b) =>
  $(sum-expr $a $b);

macro Expression $origin() => (Point) { 3, 4 };

static int doubled(int value) => value * 2;

int main(void) {
  int values[4] = { 10, 20, 30, 40 };
  int total = 0;
  // Operand positions that regroup: binary, unary, cast, index, and the
  // conditional's condition and false arm.
  printf("%d %d\n", $twice(21) * 2, $lispsum(21, 21) * 2);
  printf("%d %ld\n", -$twice(3), (long) $twice(3) % 5);
  printf("%d %d\n", values[$twice(1)], $origin().x);
  printf("%d\n", $wider(0) ? 1 : 2);
  printf("%d\n", 1 ? 9 : $wider(0) ? 7 : 8);
  // Positions that already read correctly take no parentheses: a delimited
  // argument, a tighter parent operator, and a left-associative chain.
  printf("%d %d\n", doubled($twice(21)), $twice(21) + 1);
  total = $twice(5) - 1 - 2;
  printf("%d\n", total);
  total += $twice(5);
  printf("%d\n", total);
  return 0;
}
