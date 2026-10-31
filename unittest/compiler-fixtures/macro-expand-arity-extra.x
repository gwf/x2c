int main(void) {
  expand %((1 2))
  macro Stmt(Expr $value) { printf("%d\n", $value); }
  return 0;
}
