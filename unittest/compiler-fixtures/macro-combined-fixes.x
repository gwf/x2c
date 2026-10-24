#include "x2c.x"
#include "rewrite.x"

/* A macro's match binder and a converted Var local are shared by reference
   with a lambda, the body's `using` list keeps a global declared later in
   the file under a caller's same-named local, and its interpolation's support call stays
   hidden from a program `String.join` rule. */
static int joins = 0;

macro Expression $join(Expr $sep, Expr $parts) => String.join($sep, $parts);

$rewrite($join)
meta Code count_join(Code code) {
  match (code) case $join(?sep, ?parts):
    return $!String{ (joins++, String.join($sep, $parts)) };
  return code;
}

macro Stmt $celled(Expr $caller) {
  using bias;
  match (%(5)) {
    case %(?n): {
      Var c = bias;
      Func g = %!() using &n, &c => {
        n = n + c;
        c = c + 1;
      };
      g();
      String text = %"$n ${c} ${$caller}";
      printf("%s\n", text);
    }
  }
}

static int bias = 10;

int main(void) {
  auto {
    int bias = 1000;
    Var n = 77;
    $celled(n);
    printf("%d %s %d\n", bias, n.repr(), joins);
  }
  return 0;
}
