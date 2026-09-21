#include "x2c.x"

macro Expression $fixture.bump(Expr $value) => $value += 2;

keyword bump $fixture.bump;

int main(void) {
  int count = 0;
  if (count == 0) $fixture.bump(count);
  if (count == 2) bump(count);
  while (count < 8) bump(count);
  printf("%d\n", count);
  return 0;
}
