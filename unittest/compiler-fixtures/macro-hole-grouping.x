#include "x2c.x"

typedef struct Point { int x; int y; } Point;

// An Expr hole is one operand wherever the template places it. The argument
// keeps the meaning it has at the call site, and emission parenthesizes it
// only where C precedence would otherwise regroup the result.
macro Statement $guard(Expr $condition) {
  if (!$condition) return 0;
}

macro Statement $show(Expr $value) {
  printf("%d %d %d %d\n", $value * 2, -$value, !$value, $value);
}

macro Statement $members(Expr $point, Expr $index) {
  printf("%d %d %d\n", $point.x, (int) $index, $index ? 1 : 2);
}

macro Statement $when(Expr $condition, Expr $target, Expr $value) {
  if ($condition) $target = $value;
}

macro Statement $forward(Expr $value) {
  $show(-$value);
}

static int positive(int value) {
  $guard(value > 0);
  return value;
}

int main(void) {
  int a = 3, b = 0;
  Point point = { 5, 6 };
  Point *pointer = &point;
  printf("%d %d\n", positive(-3), positive(4));
  $show(1 + 2);
  $show(a);
  $members(*pointer, a = 0);
  $when(a == 0, b, a > 0 ? 7 : 8);
  printf("%d\n", b);
  $forward(1 + 1);
  return 0;
}
