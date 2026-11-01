int main(void) {
  int total = 0;
  expand %(1 (2 3))
  macro Stmt(Expr $n) { total += $n; }
  return total;
}
