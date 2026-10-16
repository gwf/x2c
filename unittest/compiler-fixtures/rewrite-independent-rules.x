#include "x2c.x"
#include "rewrite.x"

typedef struct First { int value; } First;
typedef struct Second { int value; } Second;
macro Expression $sum(Expr $left, Expr $right) => $left + $right;

$rewrite($sum)
meta Code first_sum(Code code) {
  match (code) case $sum(?left, ?right): {
    Code lhs = left;
    if (lhs.type() == $!Type{ First })
      return $!Second{ (Second) {3} + (Second) {4} };
  }
  return code;
}

$rewrite($sum)
meta Code second_sum(Code code) {
  match (code) case $sum(?left, ?right): {
    Code lhs = left, rhs = right;
    if (lhs.type() == $!Type{ Second })
      return $!Second{ (Second) { $lhs.value + $rhs.value } };
  }
  return code;
}

int main(void) {
  First left = {1}, right = {2};
  Second result = left + right;
  printf("composed %d\n", result.value);
  return 0;
}
