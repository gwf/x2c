#include "x2c.x"

macro Decorator $tag(
  Function $function,
  Expr $value
) {
  @(Code.body $function)
}

$tag()
static int answer(void) {
  return 42;
}
