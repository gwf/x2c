#include "x2c.x"

macro Expression $version() => (1)
int first = $version();

macro Expression $version() => (2)
int second = $version();

macro Expression $nested() => (3)
macro Expression $definition_site() => ($nested())
macro Expression $nested() => (4)
int third = $definition_site();

macro Unit $increment(Expr $value) => {
  static int $(x2c.ident "answer")(void) {
    return $value + 1;
  }
}

$increment(41);

int main(void) {
  printf("%d %d %d %d\n", first, second, third, answer());
  return 0;
}
