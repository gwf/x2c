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

static int guarded(int &?value, int &?other) {
  if (!value || !other) return -1;
  return use(value) + use(other);
}

static int chained(int &?value, int &?other) =>
  value && other && use(value) > use(other);

static int joined(int &?value, int &?other) =>
  value == NULL || !other ? -1 : use(value) * use(other);

static int grouped(int &?value, int &?other) {
  if (!(value && other)) return -1;
  return use(value) - use(other);
}

static int report(int &?value, int &?other, Point &?point) {
  printf("%d %d %d %d %d %d %d\n", both(value), either(value), pick(value),
         pick_absent(value), compared(value), field(point), negated(value));
  printf("%d %d %d %d\n", guarded(value, other), chained(value, other),
         joined(value, other), grouped(value, other));
  return 0;
}

int main(void) {
  int seven = 7, three = 3;
  Point point = {4};
  report(seven, three, point);
  report(seven, NULL, point);
  return report(NULL, three, NULL);
}
