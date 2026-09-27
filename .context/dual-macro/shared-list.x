#include "meta.x"
#include <assert.h>

// Isolated model: the body is canonical AST data, not a source macro value.
meta static List sum_body(void) => %(expr ?type (op + ?left ?right));
meta static List through_second_function(List body) => body;
meta static List rebuild_sum(List syntax) {
  List body = through_second_function(sum_body()), bindings;
  if (!syntax.try_match(body, bindings)) return syntax;
  return body.replace(bindings);
}
macro Expression $rebuild(Expr $syntax) => $rebuild_sum($syntax);

int main(void) {
  int price = 19, tax = 23;
  assert($rebuild(price + tax) == 42);
  assert($rebuild(price - tax) == -4);
  puts("shared-list: one body matches and reconstructs captured syntax");
  return 0;
}
