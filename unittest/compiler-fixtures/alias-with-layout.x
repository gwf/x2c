#pragma indent
#include "x2c.x"

typedef struct Point:
  int x, y
Point

alias three to 3

int main(void):
  Point point = {1, 2}
  alias point.x as px:
    px = three
  alias py to point.y:
    py = 2
  with (point.y = 10, point.x = point.x + 1):
    printf("%d %d\n", point.x, point.y)
  printf("%d %d\n", point.x, point.y)
  return 0
