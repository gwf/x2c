#include "x2c.x"
macro Unit $forward(Type $result, Name $name, Expr $target,
  Expr $arguments, Decl $parameters...) {
  static $result $name($parameters...) { return $target($arguments); }
}
int twice(int value) { return value * 2; }
$forward(int, forwarded, twice, 3, int x, int y);
int main(void) { return forwarded(0, 0) != 6; }
