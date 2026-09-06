#include "x2c.x"

static int generated_shadow = 40;

static int outer_value(void) {
  return generated_shadow;
}

macro Statement $shadow(Expr $output, Expr $value) => {
  int $(x2c.ident "generated_shadow") = $value;
  $output = $(x2c.ident "generated_shadow");
}

int main(void) {
  int result = 0;
  $shadow(result, 42);
  printf("%d %d\n", result, outer_value());
  return 0;
}
