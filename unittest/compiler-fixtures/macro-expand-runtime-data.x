int main(void) {
  List rows = %(1 2);
  expand rows
  macro Stmt(Expr $value) { printf("%d\n", $value); }
  return 0;
}
