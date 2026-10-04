#include "x2c.x"
#include "meta.x"

/* A `$f(...)` call written in an expression binds a returned code List:
   built code, a quotation, or a Macro value's application. A data List
   stays data, and a pattern takes a code-shaped List as a pattern. */
macro Expression $sum(Expr $a, Expr $b) => $a + $b;

meta static List literal(void) => x2c_literal_int(3);
meta static List quoted(int n) => $!( ${n} + 2 );
meta static List applied(void) {
  Macro s = $sum;
  return s(4, 5);
}
meta static List data(void) => %(6 7);
meta static List any_call(void) => %(expr ? (call *));

int main(void) {
  List items = $data();
  int calls = 0;
  match (%(expr (int) (call f ()))) case $any_call(): calls = 1;
  printf("%d %d %d %d %d\n", $literal(), $quoted(1), $applied(), items.len(),
    calls);
  return 0;
}
