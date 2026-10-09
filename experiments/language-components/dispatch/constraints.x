#include "x2c.x"
#include "rewrite.x"

macro Expression $sum(Expr $left, Expr $right) => $left + $right;
macro Expression $plus_zero(Expr $value) => $value + 0;

$rewrite($plus_zero)
meta Code replace_zero(Code code) => $!int{99};

$rewrite($sum,
  $!int{${%(!and ?left)}}, $!int{${%(!and ?right)}})
meta Code replace_integer_sum(Code code) => $!int{77};

int main(void) {
  int n = 2;
  double d = 2;
  printf("literal %d %d\n", n + 0, n + 3);
  printf("typed %d %.0f %d\n", n + n, d + d, n * n);
  return 0;
}
