#include "x2c.x"

macro Decorator $increment(Expr $target) => ($target + 1)

macro Decorator $scale(
  Expr $target,
  Expr $factor
) => ($target * $factor)

macro Decorator $through_lisp(Expr $target) => (
  $(car (list $target))
)

macro Expression $wrapped(Expr $target) => (
  $increment() $target
)

static int next(void) {
  return 3;
}

int main(void) {
  printf(
    "%d %d %d %d %d %d %d\n",
    $increment() 2 * 3,
    $increment() (2 * 3),
    $increment() $scale(2) 3,
    $scale(2) $increment() 3,
    $wrapped(4),
    $increment() next(),
    $through_lisp() 6
  );
  return 0;
}
