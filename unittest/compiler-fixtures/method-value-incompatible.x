#include "x2c.x"

struct Point { int x; int y; };

int main(void) {
  Array values = %[1, 2, 3];
  struct Point p = { 1, 2 };
  values.setindex(0, p);
  return 0;
}
