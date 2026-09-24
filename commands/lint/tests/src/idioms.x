/* idioms.x -- respellings that --fix proves by the generated C. */
#include <stdio.h>

typedef struct Point { int x, y; } Point;

#define POINT_X(p) ((p)->x)

int arrow(Point *p) {
  List quoted = %(a -> b);
  return p->x + POINT_X(p);
}

int member(Map m, String s) {
  if (m.contains(s)) return 1;
  if (!m.contains(s)) return 2;
  return m.contains(s) + 1;
}

int member_value(Map m, String s) => m.contains(s);

String plain(String name) {
  puts(%"unchanged: a char * destination");
  String kept = %"hello $name";
  return %"hello";
}

int twice(int value) {
  return value * 2;
}

int twice_after(int value) {
  value++;
  return value * 2;
}

int negated(Var value) {
  if (!(value is <list>)) return 0;
  return 1;
}
