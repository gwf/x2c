#include <stdio.h>

typedef struct { int x; } Point;

static int use(int &value) => value;

static int both(int &?value) => value && use(value);

static int either(int &?value) => !value || use(value);

static int pick(int &?value) => value ? use(value) : -1;

static int pick_absent(int &?value) => !value ? -1 : use(value);

static int compared(int &?value) => NULL == value ? -1 : use(value);

static int field(Point &?point) => point != NULL && point.x > 3;

static int negated(int &?value) {
  if (!(value == NULL)) return use(value);
  return -1;
}

static int report(int &?value, Point &?point) {
  printf("%d %d %d %d %d %d %d\n", both(value), either(value), pick(value),
         pick_absent(value), compared(value), field(point), negated(value));
  return 0;
}

int main(void) {
  int seven = 7;
  Point point = {4};
  report(seven, point);
  return report(NULL, NULL);
}
