#include "x2c.x"

macro Stmt $fixture.assign(Expr $target, Expr $value) {
  $target = $value;
}

keyword assign $fixture.assign;

int main(void) {
  int target = 0;
  assign target, 42;
  return target;
}
