#pragma indent
#include "x2c.x"

typedef struct Point:
  int x, y
Point

alias 3 as three

int main(void):
  Point point = {1, 2}
  alias point.x as px:
    px = three
  with (point.y = 10, point.x = point.x + 1):
    printf("%d %d\n", point.x, point.y)
  printf("%d %d\n", point.x, point.y)
  return 0
