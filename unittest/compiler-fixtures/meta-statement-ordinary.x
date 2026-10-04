#include "x2c.x"
#include "meta.x"

/* Outside an expansion a meta call written as a whole statement binds a
   code result there too, so it may return a statement as well as an
   expression. A data List stays a runtime value. */
int total = 0;
macro Stmt $bump(Expr $amount) { total += $amount; }
meta static List quoted_statement(void) => $!{ total += 1; };
meta static List quoted_pair(void) => $!{ total += 2; total += 2; };
meta static List quoted_expression(void) => $!((void) (total += 10));
meta static List pending_statement(void) => $bump(100);
meta static List data(void) => %(a b c);
meta static void nothing(void) { }

int main(void) {
  $quoted_statement();
  $quoted_pair();
  if (total == 5) $quoted_statement();
  else $pending_statement();
  $quoted_expression();
  $pending_statement();
  $nothing();
  List items = $data();
  printf("%d %s\n", total, items.repr());
  return 0;
}
