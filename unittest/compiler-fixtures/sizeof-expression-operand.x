#include <stdio.h>

// Parenthesized `sizeof` measures any expression, as in C; a type name and a
// unary operand keep their readings.
struct point { int x, y; };

int main(void) {
  int x = 1;
  long c = 1;
  struct point p = {1, 2};
  printf("%zu %zu %zu %zu %zu %zu\n", sizeof(x + 1), sizeof((long) x),
         sizeof(c ? 'a' : 2.0), sizeof x, sizeof(struct point),
         sizeof(p.x, p));
  return 0;
}
