#include <stdio.h>
#include "x2c.x"
#include "meta.x"

/* Each application takes the previous pending application as its last
   argument, so the chain nests twelve levels deep. Expanding it costs time
   proportional to its size. */
macro Stmt $pick(Expr $c, Stmt $a, Stmt $rest) {
  if ($c) $a
  else $rest
}
macro Stmt $none(Expr $r) { $r = -2; }
macro Expression $is(Expr $x, Expr $v) => $x == $v;
macro Stmt $set(Expr $r, Expr $v) { $r = $v; }

meta static List chain(List x, List r, int n) {
  Macro pick = $pick, none = $none, is = $is, set = $set;
  List out = none(r);
  for (int i = n - 1; i >= 0; i--) {
    List v = x2c_literal_int(i * 10);
    out = pick(is(x, v), set(r, v), out);
  }
  return out;
}
macro Stmt $chained(Expr $x, Expr $r) { $chain($x, $r, 12)... }

static int choose(int x) {
  int r = -1;
  $chained(x, r);
  return r;
}

int main(void) {
  printf("%d %d %d %d\n", choose(0), choose(70), choose(110), choose(5));
  return 0;
}
