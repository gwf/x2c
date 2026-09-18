#include "x2c.x"

typedef struct Point { int x, int y; } Point;

static void boom(void) { raise %(oops); }

int main(void) {
  int direct = 1;
  int through = 1;
  int slot = 1;
  int outside = 1;
  int later = 1;
  int twin = 1, mate = 1;
  Point point = { 1, 1 };
  int *pointer = &through;
  int *cells = &slot;
  int *quiet = &outside;
  Point *cursor = &point;
  int *deferred;
  int *twins = &twin, *mates = &mate;
  deferred = &later;
  *quiet = 9;
  try {
    direct = 5;
    *pointer = 5;
    cells[0] = 5;
    cursor.x = 5;
    *deferred = 5;
    *twins = 5;
    boom();
  }
  catch %(oops *): printf("caught\n");
  printf("%d %d %d %d %d %d %d %d\n", direct, through, slot, point.x,
         outside, later, twin, *mates);
  return 0;
}
