#include "x2c.x"

typedef struct Point { int x, y; } Point;

static int sum(Point p) => p.x + p.y;
static Point make(void) { return ({5, 6}); }

// Parentheses around a brace keep its meaning: an initializer in a
// declaration, a compound literal of any other destination, or a Map.
int main(void) {
  int z = ({1});
  Point p = ({2, 3});
  int w;
  w = ({4});
  Map m = ({a: 7});
  printf("%d %d %d %d %d %s\n", z, sum(p), w, sum(({8, 9})), sum(make()),
         m.repr());
  return 0;
}
