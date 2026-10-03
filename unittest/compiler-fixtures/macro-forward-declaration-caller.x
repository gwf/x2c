#include <stdio.h>
#include "x2c.x"
macro Stmt $declare(Name $n, Expr $v) { int $n = $v; }
macro Stmt $pos(Name $out) { $declare(v, 4); v += 1; $out = v; }
int main(void) {
  int v = 7000, r = 0;
  $pos(r);
  printf("%d %d\n", r, v);
  return 0;
}
