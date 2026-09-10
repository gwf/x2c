---
slug: methods
section: love
tab: methods
---

```x2c
~#include <assert.h>
// Define a type with its own named methods.
typedef struct Point { int x, y; } *Point;

// Allocate a Point in the current Scope.
Point Point.new(int x, int y) {
  Point point = Scope.malloc(sizeof(struct Point));
  point.x = x; point.y = y;
  return point;
}

// Fields and methods both use dot notation.
void Point.move(Point point, int dx, int dy) {
  point.x += dx; point.y += dy;
}

~int main(void) {
// Create and move a Point with compact dot calls.
Point point = Point.new(1, 2);
~assert(point.x == 1 && point.y == 2);
point.move(3, 4);
~assert(point.x == 4 && point.y == 6);
~return 0;
~}
```

`Point.new` and `Point.move` give a user-defined type the same calling
style as the built-ins. Type-qualified names let other types define their
own methods without collisions. Dot notation works for both fields and
method calls; the compiler supplies the receiver argument.
