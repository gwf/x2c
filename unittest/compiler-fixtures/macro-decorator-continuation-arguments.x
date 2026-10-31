macro Decorator $bad(Expr $value) =>
  macro Decorator(Stmt $body, Expr $other) { $body };

int main(void) {
  $bad() 1
  { puts("body"); }
  return 0;
}
