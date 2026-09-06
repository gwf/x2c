#include "x2c.x"

macro Expression $raw_snapshot(Expr $value) => (
  $(list 'expr '((func ()) "Var") (list 'lambda '(params) $value))
)

int main(void) {
  int value = 1;
  Func change = $raw_snapshot(++value);
  return 0;
}
