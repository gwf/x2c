#include <math.h>
#include <stdio.h>
#include <stdlib.h>

struct point {
  const char *name;
  double x, y;
};

static double distance(const struct point *p) {
  return sqrt(p->x * p->x + p->y * p->y);
}

static int by_distance(const void *a, const void *b) {
  double da = distance(a), db = distance(b);
  return (da > db) - (da < db);
}

int main(void) {
  struct point points[] = {
    {"far", 6, 8}, {"near", 1, 1}, {"middle", 3, 4},
  };
  size_t count = sizeof points / sizeof points[0];
  qsort(points, count, sizeof points[0], by_distance);
  for (size_t i = 0; i < count; i++)
    printf("%-6s %5.2f\n", points[i].name, distance(&points[i]));
  return 0;
}
