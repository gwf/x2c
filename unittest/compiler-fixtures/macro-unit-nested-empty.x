#include "x2c.x"

/* A Unit macro may expand another Unit macro that has no parameters. */
macro Unit $inner_unit() {
  int inner_value;
}

macro Unit $outer_unit() {
  $inner_unit();
}

$outer_unit();

int main(void) {
  printf("expanded\n");
  return 0;
}
