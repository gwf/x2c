/* Nested invocations inside a template read the types of syntax the
   template left untyped: its locals, method results, and casts resolve
   where the expansion stands. */
#include "x2c.x"

macro Statement $count_local(Expr $root, Name $n) {
  List items = $root;
  foreach (Var child, items) $n++;
}

macro Statement $count_rest(Expr $root, Name $n) {
  foreach (Var child, $root.cdr()) $n++;
}

macro Statement $count_cast(Expr $root, Name $n) {
  foreach (Var child, (List) $root) $n++;
}

macro Statement $let_local(Name $n) {
  int local = 1;
  $let(local, 7) { $n += local; }
  $n += local;
}

int main(void) {
  Var tree = %(a b c d);
  int local = 0, rest = 0, cast = 0, let = 0;
  $count_local(%(a b c), local);
  $count_rest(%(a b c), rest);
  $count_cast(tree, cast);
  $let_local(let);
  printf("%d %d %d %d\n", local, rest, cast, let);
  return 0;
}
