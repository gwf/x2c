#include "x2c.x"
#include "meta.x"

/* A typed quotation's Type hole points at a type name spelled as a
   Symbol. */
typedef struct Point { int x, y; } Point;

meta static List point_size(void) {
  Type t = %(* Point);
  return $!long{ (long) sizeof($t) };
}
macro Expression $size() => $point_size();

int main(void) { return $size() == 0; }
