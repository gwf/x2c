#include "x2c.x"

macro Statement $late(Expr $value) {
  $value;
  using $temporary;
  int $temporary = 0;
}
