#include "x2c.x"
#include "rewrite.x"
#include "meta.x"

/* A rule that runs while a function body lowers places code at the entry
   of that function. The `new-name` row of the carrier it returns gives the
   placed declaration and the rewritten call one fresh local. A lambda body
   lowers as the body of its own function, so each call of the lambda
   enters that function and starts a fresh total. */

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
    Atom total = Atom.intern("?__tally");
    Code read = %(expr (int) (ident $total));
    List zero = %(expr (int) (literal (int) "0"));
    List declaration =
      %(declare (int) (bindings (op = (bind $total ()) $zero)));
    return %(code-value "source" ${$!int{ $read += $step }}
             ((new-name $total "tally")
              (place (function-entry) $declaration)));
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
