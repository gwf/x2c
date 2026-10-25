#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

/* A rule on the lambda head sees each lambda the transform lowers, before
   the shipped rule, and may answer what that rule does not. */

static int made = 0;

static Var answer(void) => 42;

$rewrite($lambda_expression)
/* A noncapturing lambda without parameters whose body is the literal 42
   is the shared `answer`, so each such Func is the same handle; any other
   lifts to a function of its own. */
meta Code share_answer(Code node) {
  match (node)
    case %(expr ? $($lambda_expression(%(expr ? (literal ? "42")), %()))):
      return $!( answer );
  return node;
}

$rewrite($lambda_captured)
/* A capturing lambda counts each Func it makes. */
meta Code count_closures(Code node) => $!(({ made++; $node; }));

int main(void) {
  Func shared = %!() => 42, again = %!() => 42, own = %!() => 7;
  int base = 3;
  Func add = %!(Var n) using &base => n.int() + base++;
  for (int i = 0; i < 2; i++) {
    Func scaled = %!(Var n) => n.int() * base;
    printf("%ld ", scaled(i).integer());
  }
  printf("%ld %ld %ld %d %d %d\n", shared().integer(), own().integer(),
         add(1).integer(), base, made, shared == again);
  return 0;
}
