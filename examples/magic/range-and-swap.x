#include "x2c.x"

macro Decorator $control.range(
  Block $body,
  Name $index,
  Expr $start,
  Expr $stop
) using $begin, $end => {
  {
    int $begin = $start, $end = $stop;
    for (int $index = $begin; $index < $end; $index++) $body
  }
}

macro Statement $control.swap(
  Expr $left,
  Expr $right
) using $temporary => {
  $(x2c.syntax.type $left) $temporary = $left;
  $left = $right;
  $right = $temporary;
}

keyword range $control.range;
keyword swap $control.swap;

int main(void) {
  int total = 0;
  int left = 20, right = 22;
  range(index, 2, 5) {
    total += index;
  }
  swap(left, right);
  printf("%d %d %d\n", total, left, right);
  return 0;
}
