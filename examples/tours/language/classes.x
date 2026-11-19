/* class generates operations for a chosen C representation. Point is a
   record value; Node is a pointer. Record copying is shallow, not
   recursive. */
class Point { int x; int y; };
class Node { int value; } *;
static void Point.move(Point &p, int dx, int dy) { p.x += dx; p.y += dy; }

int main(void) {
  auto {
    Point point = Point.new(2, 3), copy = point;
    point.move(1, 1);
    Var boxed = point; // Boxing a record copies it into owned storage.
    Map labels = {};
    labels[boxed] = "here";
    printf("classes: moved %d,%d; copy %d,%d; equal key %s\n",
           point.x, point.y, copy.x, copy.y, labels[Point.new(3, 4)]);
    Node node = auto Node.new(7);
    Node same = node;
    same.value++;
    printf("   pointer copies share: %d\n", node.value);
  }
  return 0;
}
