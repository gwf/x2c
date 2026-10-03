/* A macro body calls a `meta` function defined in the same file, as the
   book's "Calling a meta function from a macro body" sample does. */

#include "x2c.x"
#include "meta.x"

typedef struct Point { int x, y, z; } Point;

meta static List field_count(TypeInfo type) =>
  x2c_literal_int(((List) type.assoc(<fields>)).len());

macro Expression $probe.count(Expr $value) => $field_count($value);

int main(void) {
  Point p = { 1, 2, 3 };
  printf("count %d\n", $probe.count(p));
  return 0;
}
