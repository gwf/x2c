#include "x2c.x"

/* Nothing declares `x` where `$use_x` is defined, and the caller's local
   `x` does not supply it. */
macro Statement $use_x(Name $out) {
  $out = x;
}

int main(void) {
  int x = 5, result = 0;
  $use_x(result);
  printf("%d\n", result);
  return 0;
}
