#include "x2c.x"

/* A Var has no conversion to a struct that declares no Var reader, whether
   the destination names the struct by a typedef or by its tag. */

struct Point {
  int x, y;
};

int main(void) {
  Var value = 1;
  struct Point point = value;
  return point.x;
}
