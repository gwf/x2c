#include "x2c.x"

macro Expression $raw_snapshot(Expr $value) => (
  $(list 'expr '((func ()) "Var") (list 'lambda '(params) $value))
)

int main(void) {
  int value = 1;
  Func source = %!() => value;
  Func constructed = $raw_snapshot(value);
  value = 2;
  printf("source=%ld constructed=%ld\n", source().integer(),
         constructed().integer());
  return 0;
}
