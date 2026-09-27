#include "meta.x"
#include <assert.h>

macro Expression $sum(Expr $left, Expr $right) => $left + $right;
macro Expression $twice(Expr $value) => $value + $value;
macro Expression $call(Expr $callee, Expr $arguments...) =>
  $callee($arguments...);

meta static List echo(List syntax) => syntax;
macro Expression $roundtrip(Expr $value) => $echo($value);

static int add(int a, int b) => a + b;

int main(void) {
  assert($sum(19, 23) == 42);
  assert($twice(21) == 42);
  assert($call(add, 19, 23) == 42);
  assert($roundtrip(19 + 23) == 42);
  List tree = %(op + (ident price) (ident tax));
  List pat = %(op + ?left ?right);
  List rows;
  assert(tree.try_match(pat, rows));
  assert(pat.replace(rows).equal(tree));
  assert(%(op + (ident price) (ident price)).match(%(op + ?x ?x)));
  assert(!tree.match(%(op + ?x ?x)));
  List call = %(call (ident add) (args 19 23));
  List call_pat = %(call ?callee (args *arguments));
  assert(call.try_match(call_pat, rows));
  assert(call_pat.replace(rows).equal(call));
  assert(%(call (ident add) (args)).try_match(call_pat, rows));
  assert(call_pat.replace(rows).equal(%(call (ident add) (args))));
  puts("baseline: construction, meta echo, repeat, sequence roundtrips pass");
  return 0;
}
