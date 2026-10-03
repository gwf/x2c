#include "x2c.x"

/* Nothing declares `x` where `$use_x` is defined, so the name resolves where
   the expansion lands, and the caller's local `x` supplies it. */
macro Stmt $use_x(Name $out) {
  $out = x;
}

int main(void) {
  int x = 5, result = 0;
  $use_x(result);
  printf("%d\n", result);
  return 0;
}
