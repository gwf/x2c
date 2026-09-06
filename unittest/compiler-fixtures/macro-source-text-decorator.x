#include "x2c.x"

macro Decorator $show_source(Function $target) => {
  printf("[%s]\n", $(x2c.literal.string (x2c.source.text $target)));
  $(x2c.function.body $target)...
}

$show_source()
static int decorated(void) {
  return 7;
}

int main(void) {
  return decorated() == 7 ? 0 : 1;
}
