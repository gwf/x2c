#include <stdio.h>

typedef struct Point { int x, y; } Point;

meta static List field_rows(List fields) {
  Array rows = [];
  foreach (Var field in fields) rows.push($(field));
  return rows.list_free();
}

macro Stmt $copy(Expr $to, Expr $from, Name @fields) {
  expand $field_rows($fields)
  macro Stmt(Name $field) { $to.$field = $from.$field; }
}

meta static List pair_rows(void) => %(("left" 1) ("right" 2));

macro Unit $pairs() {
  expand $pair_rows()
  macro Unit(Name $name, Expr $value) { static int $name(void) { return $value; } }
}

$pairs();

int main(void) {
  Point from = { 3, 4 }, to = { 0, 0 };
  $copy(to, from, x, y);
  printf("%d %d %d %d\n", to.x, to.y, left(), right());
  return 0;
}
