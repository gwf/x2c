#include <stdio.h>

// Parenthesized `sizeof` measures any expression, as in C; a type name, a
// compound literal, and a unary operand keep their readings.
struct point { int x, y; };
typedef struct point P;

static int *touch(int *xs, int *calls) {
  *calls += 1;
  return xs;
}

int main(void) {
  int x = 1;
  long c = 1;
  struct point p = {1, 2};
  int xs[3] = {1, 2, 3}, side_effect = 0;
  printf("%zu %zu %zu %zu %zu %zu\n", sizeof(x + 1), sizeof((long) x),
         sizeof(c ? 'a' : 2.0), sizeof x, sizeof(struct point),
         sizeof(p.x, p));
  printf("%zu %zu %zu %zu %d\n", sizeof xs, sizeof (xs),
         sizeof (xs)[0], sizeof (touch(xs, &side_effect))[0], side_effect);
  printf("%zu %zu %zu\n", sizeof (int[]){1, 2, 3}, sizeof (P){1, 2},
         sizeof (P){1, 2}.y);
  return 0;
}
