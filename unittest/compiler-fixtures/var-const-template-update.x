#include "x2c.x"

macro Stmt $update(Expr $target, Expr $step) { $target += $step; }

int main(void) {
  const int target = 3;
  Var step = 1;
  $update(target, step);
  return 0;
}
