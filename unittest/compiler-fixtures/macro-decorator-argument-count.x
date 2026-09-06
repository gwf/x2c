#include "x2c.x"

macro Decorator $tag(
  Function $function,
  Expr $value
) => {
  $(x2c.function.body $function)...
}

$tag()
static int answer(void) {
  return 42;
}
