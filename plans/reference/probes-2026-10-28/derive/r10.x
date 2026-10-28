#include "x2c.x"
#include "meta.x"
typedef struct Point { int x; } Point;
Point Point.from_map(Map m) { Point p = { m["x"] }; return p; }
meta static List build(Type t, List m) {
  List n = x2c_ident(%"$(t.car())_from_map");
  return $!( $n($m) );
}
macro Expression $probe.build(Type $t, Expr $m) => $build($t, $m);
int main(void) {
  Map m = {"x": 7};
  Point p = Point_from_map(m);
  Point q = $probe.build(Point, m);
  printf("%d %d\n", p.x, q.x);
  return 0;
}
