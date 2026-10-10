/* A function rule sees each bound and typed definition before its body
   lowers and may return a replacement definition. A replacement is not
   offered again to the rule that returned it, and a rule whose pattern
   spells the return type comes before a rule whose pattern holds a hole
   there. */

#include "x2c.x"
#include "rewrite.x"

static int entries = 0;

macro Unit $any_function(Function $function) { $function }

/* Counts the calls of each function named `counted_...` and declines every
   other function. */
$rewrite($any_function)
meta Code count_entries(Code function) {
  if (!x2c_function_name(function).startswith("counted_")) return function;
  match (function) case %(function ?type ?declarator ?):
    return %(function $type $declarator
      (block ${$!{ entries++; }} @{x2c_function_body(function)}));
  return function;
}

macro Unit $int_unary(Name $name, Param $parameter, Expr $value) {
  int $name($parameter) { return $value; }
}

/* Doubles the result of an `int` function of one parameter whose one
   returned expression has type `int`, and declines the others. */
$rewrite($int_unary)
meta Code double_result(Code function) {
  match (function) case $int_unary(?name, ?parameter, ?value): {
    Code returned = value;
    if (returned.type() == %(int))
      return $!Unit{ int $name($parameter) { return 2 * ($value); } };
  }
  return function;
}

int counted_next(int x) { return x + 1; }
int counted_pair(int a, int b) { return a + b; }
int plain(int x) { return x - 1; }
int narrow(long value) { return value; }
static int hidden(int x) { return x; }

int counted_lambda(int base) {
  int total = 0;
  Func add = %!(int v) using &total => { total += v + base; return total; };
  add(1);
  (int a, int b) = [10, 20];
  defer printf("deferred %d\n", total);
  try {
    if (total > 0) raise %(found);
  }
  catch %(found): total += a + b;
  return total;
}

int main(void) {
  printf("%d %d\n", counted_next(1), counted_pair(2, 3));
  printf("%d %d %d\n", plain(5), narrow(7L), hidden(9));
  printf("%d\n", counted_lambda(5));
  printf("%d\n", entries);
  return 0;
}
