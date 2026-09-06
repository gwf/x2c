#include "x2c.x"

macro Decorator $fixture.twice(Expr $target) => ($target * 2)

keyword twice $fixture.twice;

int main(void) {
  printf("%d\n", twice (20 + 1));
  return 0;
}
