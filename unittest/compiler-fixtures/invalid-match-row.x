#include "x2c.x"

macro Stmt $pick(Expr $subject, MatchRow $rows...) {
  match ($subject) { $rows... }
}

int main(void) {
  List x = %(a);
  int hit = 0;
  $pick(x, case %(a): hit = 1;);
  $pick(x, hit = 2);
  return hit;
}
