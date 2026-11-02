#include "x2c.x"

/* A destination spelled with a struct tag converts as the typedef that names
   the same struct, so both spellings read a Var through `Var.point`. */

typedef struct Point {
  int x, y;
} Point;

static Point Var.point(Var value) {
  Point point = {value.int(), 2};
  return point;
}

int main(void) {
  Var value = 1;
  Point named = value;
  struct Point tagged = value;
  printf("%d %d\n", named.x + named.y, tagged.x + tagged.y);
  return 0;
}
