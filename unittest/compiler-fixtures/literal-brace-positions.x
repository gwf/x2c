#include "x2c.x"

typedef struct Point { int x, y; } Point;

static int is_null(Var v) => v == NULL;
static int second(Point p) => p.y;
static Point make(void) { return {3, 4}; }
static Var none(void) { return {}; }

// A brace outside a declaration is a compound literal of its destination,
// and an empty brace inside a bare literal is an empty Map.
int main(void) {
  Var v = 3;
  v = {};
  Point q;
  q = {5, 6};
  Map m = {};
  m[<k>] = {};
  printf("%d %d %d %d %d\n", is_null({}), is_null(v), second({1, 2}),
         make().y, q.y);
  printf("%s %s %s %s\n", none().repr(), m.repr(), [{}].repr(),
         {d: {}}.repr());
  Var array = (Var) [1, 2];
  printf("%s %d\n", array.repr(), (int) (long) [1].len());
  return 0;
}
