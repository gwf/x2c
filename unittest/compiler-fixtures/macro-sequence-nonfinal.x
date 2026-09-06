#include "x2c.x"

macro Expression $call(Expr $arguments..., Expr $final) => ($final)

int main(void) {
  return $call(1, 2);
}
