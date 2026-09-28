#include "x2c.x"

macro Unit $accessor(Name $name, Param $left, Param $right, Expr $body) {
  static int $name($left, $right) { return $body; }
}

macro Expression $made(Param $params...) => %!($params...) => 41;

$accessor(sum, int x, int y, x + y);
$accessor(difference, short x, short y, x - y);

int main(void) {
  Func first = $made(int value);
  Func second = $made(short value);
  printf("%d %d %d %d\n", sum(7, 5), difference(7, 4),
         first(0).int(), second(0).int());
  return 0;
}
