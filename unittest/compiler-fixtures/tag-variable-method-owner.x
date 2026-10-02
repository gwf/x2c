#include "x2c.x"

struct Point { int n; };
struct Point Point;
static int Point_value(struct Point p) => 9;

int main(void) {
  struct Point point = {3};
  return point.value();
}
