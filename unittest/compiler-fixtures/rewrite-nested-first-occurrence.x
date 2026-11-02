#include "x2c.x"
#include "rewrite.x"

/* A source value lowers outside every rule whose translator captured it,
   so in `f(f(x))` the inner call takes both rules, on the first use of a
   replacement as on later ones. */
static int f(int x) { return x + 1; }
static int g(int x) { return x * 10; }
static int h(int x) { return x + 100; }

macro Expression $f_call(Expr $x) => f($x);
macro Expression $g_call(Expr $x) => g($x);

$rewrite($f_call)
meta Code f_to_g(Code code) {
  match (code) case $f_call(?x): {
    Code value = x;
    return $!int{ g($value) };
  }
  return code;
}

$rewrite($g_call)
meta Code g_to_h(Code code) {
  match (code) case $g_call(?x): {
    Code value = x;
    return $!int{ h($value) };
  }
  return code;
}

int main(void) {
  printf("%d %d %d\n", f(f(1)), f(f(1)), f(f(2)));
  return 0;
}
