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

/* A value whose body calls a global recognizes the expanded call and binds
   the callee again where it is applied. */
static int bump(int value) { return value + 1; }
macro Expression $inc(Expr $value) => bump($value);
meta static List increment_operand(List code) {
  match (code) {
    case $inc(?value): return value;
  }
  return code;
}
meta static List increment(List code) {
  Macro inc = $inc;
  return inc(code);
}
macro Expression $inc_operand(Expr $code) => $increment_operand($code);

/* A free callee resolves where its expansion lands. Recognition accepts
   that same local, while an explicit `using` callee keeps the global. */
static int decrement(int value) { return value - 1; }
meta static List increment_hit(List code) {
  match (code) {
    case $inc(?value): return x2c_literal_int(1);
  }
  return x2c_literal_int(0);
}
macro Expression $is_inc(Expr $code) => $increment_hit($code);
macro Expression $inc_again(Expr $code) => $increment($code);
macro Expression $global_inc(Expr $value) using bump => bump($value);
meta static List global_increment_hit(List code) {
  match (code) case $global_inc(?value): return x2c_literal_int(1);
  return x2c_literal_int(0);
}
macro Expression $is_global_inc(Expr $code) => $global_increment_hit($code);

/* This private callee has a different mark from the independent $inc. */
macro Stmt $private_callee_check(Expr $value) {
  int (*bump)(int) = decrement;
  printf("%d %d %d %d %d\n", $inc($value), $is_inc($inc($value)),
         $is_inc(bump($value)), $is_global_inc(bump($value)),
         $is_global_inc($global_inc($value)));
}

int main(void) {
  int price = 19, tax = 23;
  printf("%d\n", $stage_cases(price, tax, $sum(price, tax)));
  printf("%d\n", $left_of(price + tax));
  printf("%d\n", $twice(tax));
  printf("%d %d\n", $inc_operand($inc(price)), $inc_again(price));
  int global_hit = $is_inc(bump(price)), local_hit;
  int built_value, built_hit, kept_hit, kept_miss;
  {
    int (*bump)(int) = decrement;
    local_hit = $is_inc(bump(price));
    built_value = $inc(price);
    built_hit = $is_inc($inc(price));
    kept_hit = $is_global_inc($global_inc(price));
    kept_miss = $is_global_inc(bump(price));
  }
  printf("%d %d %d %d %d %d\n", global_hit, local_hit, built_value,
         built_hit, kept_hit, kept_miss);
  $private_callee_check(price);
  return 0;
}
