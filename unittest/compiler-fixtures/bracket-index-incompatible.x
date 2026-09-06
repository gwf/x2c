#include "x2c.x"

struct Point { int x; int y; };

int main(void) {
  Map scores = %{ one: 1 };
  struct Point p = { 1, 2 };
  Var hit = scores[p];
  (void) hit;
  return 0;
}
