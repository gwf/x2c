#include "meta.x"
macro Expression $sum(Expr $left, Expr $right) => $left + $right;
meta static List unavailable(void) {
  List value = $sum;
  return value;
}
