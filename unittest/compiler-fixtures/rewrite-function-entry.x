#include "x2c.x"
#include "rewrite.x"
#include "meta.x"

/* A rule that runs while a function body lowers places code at the entry
   of that function. `x2c_binding_fresh` gives the placed declaration and
   the rewritten call one fresh local. A lambda body lowers as the body of
   its own function, so each call of the lambda enters that function and
   starts a fresh total. */

static int tally(int step) => step;

macro Expression $tallied(Expr $step) => tally($step);

$rewrite($tallied)
meta Code count_tally(Code code) {
  match (code) case $tallied(?step): {
    String name = Code.name(x2c_enclosing(<function>));
    x2c_place(
      %(function-entry),
      $!{
        printf("enter %s\n", $name);
        defer printf("leave %s\n", $name);
      });
    List total = x2c_binding_fresh("tally");
    x2c_place(%(function-entry), $!{ int $total = 0; });
    Code read = $!int{ $total };
    return $!int{ $read += $step };
  }
  return code;
}

static int run(int count) {
  printf("first statement\n");
  int last = 0;
  for (int i = 1; i <= count; i++) last = tally(i);
  return last;
}

int main(void) {
  printf("%d\n", run(3));
  int base = 100;
  Func plain = %!(Var n) => tally(n.int());
  Func shared = %!(Var n) using &base => tally(n.int()) + base;
  printf("%d %d\n", plain(1).int(), plain(2).int());
  printf("%d %d\n", shared(1).int(), shared(2).int());
  return 0;
}
