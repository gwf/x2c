#include "x2c.x"
#include "meta.x"

/* A template writes a lambda whose parameters are a Param sequence, and
   a case on it recognizes a lambda and captures its body. */
macro Expression $lam(Expr $body, Param $params...) => %!($params...) => $body;
meta static List lambda_body(List code) {
  Macro lam = $lam;
  match (code) { case lam(?body, *params): return body; }
  return x2c_literal_int(0);
}
macro Expression $body_of(Expr $code) => $lambda_body($code);
int main(void) {
  Func f = %!(x) => x + 1;
  (void) f;
  int n = $body_of(%!(int y) => 41);
  printf("%d\n", n);
  return 0;
}
