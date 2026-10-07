#include "x2c.x"
#include "meta.x"

/* A slot passes a sequence hole to a meta function as one List, a client
   passes a List as the whole sequence, and a case on the macro captures
   the slot's output under that hole, element by element. */
static int total;
macro Stmt $add(Expr $x) { total += $x; }
meta static List parts(List xs) {
  Array rows = [];
  Macro add = $add;
  foreach (List x, xs) rows.push(add(x));
  return rows.list_free();
}
macro Stmt $outer(Expr $head, Expr @xs) {
  {
    total = $head;
    @parts($xs)
  }
}
meta static List build(List head, List a, List b) {
  Macro outer = $outer;
  return outer(head, %($a $b));
}
meta static List summary(List code) {
  Macro outer = $outer, add = $add;
  int n = 0;
  match (code) {
    case outer(?head, *items):
      foreach (List item, items) match (item) { case add(?x): n++; }
  }
  return x2c_literal_int(n);
}
macro Stmt $built(Expr $h, Expr $a, Expr $b) { @build($h, $a, $b) }
macro Expression $count_adds(Stmt $s) => $summary($s);
int main(void) {
  $built(1, 2, 3);
  int n = $count_adds({ total = 5; total += 6; total += 7; });
  printf("%d %d\n", total, n);
  return 0;
}
