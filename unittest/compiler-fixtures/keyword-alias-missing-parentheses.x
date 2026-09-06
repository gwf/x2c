#include "x2c.x"

macro Statement $fixture.assign(Expr $target, Expr $value) => {
  $target = $value;
}

keyword assign $fixture.assign;

int main(void) {
  int target = 0;
  assign target, 42;
  return target;
}
