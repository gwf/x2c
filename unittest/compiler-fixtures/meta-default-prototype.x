/* A bodyless `meta` prototype of a class default in the class's own file
   leaves the default to supply the definition, and a written definition
   still replaces the default. Only a compiler built with this unit could
   call the native target at compile time, so the run-time calls prove that
   both definitions link. */

#include "x2c.x"

class Point struct { int x; int y; };
class Pair struct { int left; int right; };

meta int Point.equal(Point left, Point right);

int Pair.equal(Pair a, Pair b) { return 7; }

int main(void) {
  Point left = { .x = 3, .y = 4 };
  Point right = { .x = 3, .y = 5 };
  Pair pair = { .left = 1, .right = 2 };
  printf("%d %d %d\n", left.equal(left), left.equal(right),
    pair.equal(pair));
  return 0;
}
