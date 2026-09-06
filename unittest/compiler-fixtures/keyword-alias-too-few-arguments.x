#include "x2c.x"

macro Expression $fixture.add(Expr $left, Expr $right) => (
  $left + $right
)

keyword add $fixture.add;

int main(void) {
  return add(1);
}
