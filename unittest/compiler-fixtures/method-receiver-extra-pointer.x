/* `.` binds a method receiver by identity or by one address-of. A receiver
   that is a pointer to the declared parameter would call through the wrong
   pointer; for a pointer typedef C only warns and the program aborts. */
#include "x2c.x"

class Point { int x; int y; };

void Point.init(Point *point) { point->x = 0; point->y = 0; }
int Point.equal(Point a, Point b) { return a.x == b.x && a.y == b.y; }
unsigned Point.hash(Point point) { return point.x * 31 + point.y; }
int Point.sum(Point point) { return point.x + point.y; }

static int first(List *values) { return values.car().int(); }

static int total(Point *point) { return point.sum(); }

int main(void) {
  List values = [1];
  Point point = { 3, 4 };
  return first(&values) + total(&point);
}
