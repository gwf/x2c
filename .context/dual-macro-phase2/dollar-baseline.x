#include "x2c.x"
#include <assert.h>

static int sum(int left, int right) => 100 + left + right;
macro Expression $sum(Expr $left, Expr $right) => $left + $right;

int main(void) {
  assert($sum(1, 2) == 3);
  assert(sum(1, 2) == 103);
  int (*ordinary)(int, int) = sum;
  assert(ordinary(1, 2) == 103);
  {
    macro Expression sum(Expr $left, Expr $right) =>
      20 + $left + $right;
    assert(sum(1, 2) == 23);
    assert($sum(1, 2) == 3);
    assert((sum)(1, 2) == 103);
    int (*still_ordinary)(int, int) = sum;
    assert(still_ordinary(1, 2) == 103);
  }
  puts("dollar baseline: global, local, ordinary calls and bare references pass");
  return 0;
}
