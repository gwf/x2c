/* Classes choose representations, not an object hierarchy. A record copies
   its fields. A pointer class copies its handle. Reference methods borrow
   the original record; no & is needed at the call. */
class Point { int x; int y; };
class Node { int value; } *;
static void Point.move(Point &p, int dx, int dy) { p.x += dx; p.y += dy; }

int main(void) {
  auto {
    Point point = Point.new(2, 3), copy = point;
    point.move(1, 1);
    Node node = auto Node.new(7);
    Node same = node;
    same.value++;
    printf("classes: point %d,%d; copy %d,%d; shared node %d\n",
           point.x, point.y, copy.x, copy.y, node.value);
    // A record containing an Array would copy that handle, not its contents.
  }
  return 0;
}
