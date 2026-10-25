#include "x2c.x"

meta static List raw_snapshot_of(List value) =>
  %(expr ((func ()) "Var") (lambda (params) $value));

macro Expression $raw_snapshot(Expr $value) => $raw_snapshot_of($value);

int main(void) {
  int value = 1;
  Func change = $raw_snapshot(++value);
  return 0;
}
