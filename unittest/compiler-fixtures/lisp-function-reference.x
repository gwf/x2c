#include "x2c.x"

static int twice(int value) {
  return value * 2;
}

/* `_x2c.function.reference` reads the symbol table, so an inline
   compile-time Lisp form outside any macro expansion may call it. */
int main(void) {
  int doubled = $(x2c.expr.call
    (_x2c.function.reference "twice") (x2c.literal.int 21));
  printf("%d\n", doubled);
  return 0;
}
