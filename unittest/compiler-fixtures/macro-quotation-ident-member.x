#include "x2c.x"
#include "meta.x"

/* An `x2c_ident` local in a member position selects the member it spells,
   after `.` or `->`, on first use or after a declaration. */
typedef struct P { int x, y; } P;

meta static List dot(List object) {
  List field = x2c_ident("y");
  return $!( $object.$field + 1 );
}

meta static List arrow(List pointer) {
  List field = x2c_ident("y");
  return $!( $pointer->$field * 10 );
}

meta static List shadowed(List object) {
  List field = x2c_ident("x");
  return $!( ({ int $field = 5; $object.$field + $field; }) );
}

meta static List spelled(List object) {
  String field = "x";
  return $!( $object.$field - 1 );
}

macro Expression $dot_of(Expr $o) => $dot($o);
macro Expression $arrow_of(Expr $o) => $arrow($o);
macro Expression $shadowed_of(Expr $o) => $shadowed($o);
macro Expression $spelled_of(Expr $o) => $spelled($o);

int main(void) {
  P p = {1, 2};
  P *pp = &p;
  printf("%d %d %d %d\n", $dot_of(p), $arrow_of(pp), $shadowed_of(p),
    $spelled_of(p));
  return 0;
}
