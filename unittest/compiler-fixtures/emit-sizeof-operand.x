#include "x2c.x"

/* C reads only a unary expression after `sizeof`, so a binary or cast
   operand that a template supplies is grouped, and a unary one is not. */
macro Expression $size_of(Expr $value) => sizeof $value;

int main(void) {
  char a = 1;
  int b = 10, *p = &b;
  printf("%d %d %d\n", (int) $size_of(a + b), (int) $size_of((char) -b),
         (int) $size_of(*p));
  return 0;
}
