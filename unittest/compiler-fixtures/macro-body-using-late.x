#include "x2c.x"

macro Stmt $late(Expr $value) {
  $value;
  using $temporary;
  int $temporary = 0;
}
