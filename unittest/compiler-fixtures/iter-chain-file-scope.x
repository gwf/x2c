#include "x2c.x"

/* A file-scope initializer completes the chain it consumes, as a function
   body does. */

List squares = range(1, 4, 1);
static int evens = range(0, 6, 2).count();

int main(void) {
  printf("%s %d\n", squares.repr(), evens);
  return 0;
}
