int main(void) {
  expand %((1))
  macro Stmt(Expr $left, Expr $right) { printf("%d\n", $left + $right); }
  return 0;
}
