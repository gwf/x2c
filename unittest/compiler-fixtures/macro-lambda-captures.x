#include "x2c.x"
#include "meta.x"

macro Expression $captured(Expr $body, Captures $captures,
    Param @params) => %!(@params) using $captures => $body;
macro Expression $plain(Expr $body, Param @params) =>
  %!(@params) => $body;

meta static List rebuild(List code) {
  Macro captured = $captured, plain = $plain;
  match (code) {
    case captured(?body, *captures, *params):
      return captured(body, captures, params);
    case plain(?body, *params): return plain(body, params);
  }
  x2c_diagnostic_fail("expected a lambda", NULL);
}
macro Expression $again(Expr $code) => $rebuild($code);

int main(void) {
  int snapshot = 10, shared = 2;
  Func f = $again(%!(int n) using &shared => snapshot + shared + n);
  snapshot = 30;
  shared = 4;
  printf("%d\n", f(3).int());
  Func g = $again(%!() using &shared => { shared++; return shared; });
  int changed = g().int();
  printf("%d %d\n", changed, shared);
  Func h = $again(%!(int a, int b) => a + b);
  printf("%d\n", h(5, 6).int());
  return 0;
}
