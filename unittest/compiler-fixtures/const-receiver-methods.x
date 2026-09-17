#include "x2c.x"

typedef struct Point { int x, int y; } Point;

static int Point.sum(Point self) => self.x + self.y;

static const String greeting = "hi";

static int width(const String text) => text.len();

int main(void) {
  const String name = "abc";
  const List items = %(1 2 3);
  const Map table = %{ "k": 1 };
  const Array cells = [1, 2];
  const Var boxed = 3;
  const Point point = { 1, 2 };
  String joined = name + "d";
  int total = 0;
  foreach (Var item, items) total += item.int();
  printf("%d %d %d %d %d %d %d %d %d %d\n",
         greeting.len(), width(name), name.upper().len(), items.len(),
         table.len(), (int) cells.len(), boxed.int(), point.sum(),
         joined.len(), name[0] == 'a' ? total : 0);
  return 0;
}
