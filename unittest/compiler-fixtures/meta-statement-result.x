#include "x2c.x"
#include "meta.x"

/* Inside an expansion a meta call written as a whole statement may return
   a statement, in an arrow body or a braced one. */
meta static List same_of(List code) { return code; }
meta static void nothing(void) { }
macro Stmt $same(Stmt $code) => $same_of($code);
macro Stmt $braced(Stmt $code) { $same_of($code); }
macro Stmt $quiet() => $nothing();

int carriers = 0;
meta static int evaluations(int add) {
  static int count;
  return count += add;
}
macro Stmt $increment_statement() { carriers += 1; }
macro Expression $increment_expression() => (carriers += 1);
meta static List quoted_statement(void) {
  evaluations(1);
  return $!{ carriers += 1; };
}
meta static List quoted_expression(void) {
  evaluations(1);
  return $!void{ (void) (carriers += 1) };
}
meta static List pending_statement(void) {
  evaluations(1);
  return $increment_statement();
}
meta static List pending_expression(void) {
  evaluations(1);
  return %("x2c.template" "increment_expression" ());
}
macro Stmt $from_quoted_statement() => $quoted_statement();
macro Stmt $from_quoted_expression() => $quoted_expression();
macro Stmt $from_pending_statement() => $pending_statement();
macro Stmt $from_pending_expression() => $pending_expression();

int main(void) {
  int total = 0;
  $same(try total += 1; finally total += 10;);
  if (total == 11)
    $same(try raise %(bad-arg (value 7));
          catch %(bad-arg (value ?value)): total += value.int(););
  $braced(defer printf("%d\n", total););
  $braced(if (total == 18) total += 100;);
  $same(total += 1000;);
  $quiet();
  $from_quoted_statement();
  $from_quoted_expression();
  $from_pending_statement();
  $from_pending_expression();
  return total != 1118 || carriers != 4 || $evaluations(0) != 4;
}
