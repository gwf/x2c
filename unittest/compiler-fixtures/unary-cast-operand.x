#include <stdio.h>

// As in C, `~` takes a cast-expression operand like `-` and `!`; only `++`
// and `--` take a unary-expression.
int main(void) {
  int n = 3;
  unsigned m = ~(unsigned) n;
  printf("%u %d %d %d %d\n", m, ~(int) -n, ~~n, ~-n, -~n);
  return 0;
}
