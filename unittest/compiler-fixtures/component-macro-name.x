/* A program meta function named like a shipped component macro is the
   one a `$name(...)` call reaches: component macros take reserved
   `x2c.` spellings. */

#include "x2c.x"

#include <stdio.h>

meta int collection_store(int a, int b, int c) => a * 100 + b * 10 + c;

int main(void) {
  printf("%d\n", $collection_store(1, 2, 3));
  return 0;
}
