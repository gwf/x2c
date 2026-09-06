#include "x2c.x"

macro Statement $stable_assign(Expr $target, Expr $value)
  using $temporary => {
  int $temporary = $value;
  $target = $temporary;
}

int main(void) {
  int value = 0;
  $stable_assign(value, 42);
  printf("%d\n", value);
  return 0;
}
