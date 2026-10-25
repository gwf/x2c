#include "x2c.x"
#include "meta.x"

/* In quotation code, `$(expression)` computes while the quotation is built.
   Inside a percent literal, `$(expression)` inserts at run time, and a
   nested `$(...)` there computes at construction again. */
meta static List offset(List operand, int amount) =>
  $!( $operand + $(amount + 1) );
macro Expression $shifted(Expr $e) => $offset($e, 4);

static int calculate(void) => 42;
meta static List runtime_answer(void) => $!( %(answer $(calculate())) );
macro Expression $ran() => $runtime_answer();
meta static List built_answer(int amount) => $!( %(answer $($(amount + 1))) );
macro Expression $built() => $built_answer(9);
meta static List listed(List a, List b) => $!( %( $($a) $($b) ) );
macro Expression $pair(Expr $a, Expr $b) => $listed($a, $b);
static int sum(int a, int b) => a + b;
meta static List summed(List items) => $!( sum(@(items)) );
macro Expression $spread() => $summed(%(3 4));

int main(void) {
  int x = 1;
  printf("%d\n", $shifted(x));
  printf("%s\n", $ran().repr());
  printf("%s\n", $built().repr());
  printf("%s\n", $pair(x, x + 1).repr());
  printf("%d\n", $spread());
  return 0;
}
