#include "x2c.x"
#include "meta.x"

macro Expression $sum(Expr $left, Expr $right) => $left + $right;
macro Expression $product(Expr $left, Expr $right) => $left * $right;

/* Construction returns a pending invocation; the same case recognizes it
   before and after expansion, and a different macro's result fails. */
meta static List stages(Macro sum, Macro product, List left, List right,
                        List expanded) {
  List pending = sum(left, right);
  List wrong = product(left, right);
  int pending_hit = 0, body_hit = 0, wrong_hit = 0;
  match (pending) {
    case sum(?a, ?b):
      pending_hit = List.compare(a, left) == 0 &&
                    List.compare(b, right) == 0;
  }
  match (expanded) {
    case sum(?a, ?b):
      body_hit = List.compare(a, left) == 0 &&
                 List.compare(b, right) == 0;
  }
  match (wrong) {
    case sum(?a, ?b): wrong_hit = 1;
  }
  if (!pending_hit || !body_hit || wrong_hit)
    x2c_diagnostic_fail("macro value cases failed",
      %(${%"hits: $pending_hit $body_hit $wrong_hit"}));
  return pending;
}
macro Expression $stage_cases(Expr $left, Expr $right, Expr $expanded) =>
  $stages($sum, $product, $left, $right, $expanded);

/* A named case selects the macro directly. */
meta static List left_operand(List code) {
  match (code) {
    case $sum(?left, ?right): return left;
  }
  return code;
}
macro Expression $left_of(Expr $code) => $left_operand($code);

/* An anonymous macro is a value like any other. */
meta static Macro make_twice(void) =>
  macro Expression(Expr $value) => $value + $value;
meta static List doubled(List code) {
  Macro twice = make_twice();
  return twice(code);
}
macro Expression $twice(Expr $code) => $doubled($code);

int main(void) {
  int price = 19, tax = 23;
  printf("%d\n", $stage_cases(price, tax, $sum(price, tax)));
  printf("%d\n", $left_of(price + tax));
  printf("%d\n", $twice(tax));
  return 0;
}
