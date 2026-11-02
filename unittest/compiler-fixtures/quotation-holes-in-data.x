#include "x2c.x"

/* A hole's name keeps its meaning inside quoted data, even where a
   variable of the same name is visible at the expansion site. */
macro Expression $listed(Expr @items) => %(x @items);
macro Expression $arrayed(Expr @items) => %[0, @items];
macro Expression $labeled(Expr $value) => %"value=$value";
macro Stmt $boom(Expr $code, Expr $op) { raise %($code (operation $op)); }

int main(void) {
  List items = %(from site);
  int op = 77, value = 0;
  printf("%s %s\n", $listed(1, 2).repr(), $arrayed(1, 2).repr());
  printf("%s\n", $labeled(5));
  try { $boom(<bad>, "real-op"); }
  catch %(bad (operation ?o)): printf("op=%s\n", o.repr());
  return 0;
}
