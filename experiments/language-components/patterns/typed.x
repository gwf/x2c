#include "x2c.x"

macro Expression $sum(Expr $left, Expr $right) => $left + $right;
macro Expression $negative(Expr $value) => -$value;

meta List integer_sum(void) {
  Macro sum = $sum;
  List shape = sum.pattern(%(?left ?right));
  return $!int{ $shape };
}

meta List integer_left_sum(void) {
  Macro sum = $sum, negative = $negative;
  List inner = negative.pattern(%(?value));
  List typed = $!int{ $inner };
  return sum.pattern(%((!and $typed) ?right));
}

meta List classify_left(List code) {
  List pattern = integer_left_sum();
  int matched = !!code.match(pattern);
  return $!int{ $matched };
}

meta List classify(List code) {
  List pattern = integer_sum();
  int matched = !!code.match(pattern);
  return $!int{ $matched };
}

macro Expression $integer_sum(Expr $code) => $classify($code);

macro Expression $integer_left(Expr $code) => $classify_left($code);

int main(void) {
  int i = 3;
  double d = 3;
  printf("%d %d %d\n", $integer_sum(i + i),
    $integer_sum(d + d), $integer_sum(i * i));
  printf("%d %d %d\n", $integer_left(-i + d),
    $integer_left(-d + i), $integer_left(i + d));
  return 0;
}
