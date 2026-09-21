#include "x2c.x"

macro Statement $assign(Expr $target, Expr $value) {
  using $temporary;
  int $temporary = $value;
  $target = $temporary;
}

macro Expression $twice(Expr $value) => $value * 2;

macro Expression $grouped(Expr $value) => ($value) + 2;

macro Decorator $increment(Expr $target) => $target + 1;

macro Unit $define_generated(Name $name) {
  int $name(void) => 7;
}

macro Statement $legacy_assign(Expr $target, Expr $value)
  using $temporary => {
  int $temporary = $value;
  $target = $temporary;
}

macro Expression $legacy_increment(Expr $value) => ($value + 1)

$define_generated(generated);

static int local_macro(int value) {
  macro Expression add_one(Expr $input) => $input + 1;

  (void) (value);
  return add_one(value);
}

int main(void) {
  int result = 0;
  $assign(result, 5);
  $legacy_assign(result, result + 1);
  printf("%d %d %d %d %d %d %d\n",
         result, $twice(4), $grouped(4), $increment() 4,
         $legacy_increment(4), generated(), local_macro(4));
  return 0;
}
