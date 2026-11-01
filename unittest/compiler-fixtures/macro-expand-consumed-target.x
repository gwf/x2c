int main(void) {
  int total = 0;
  expand %(1 2)
  macro Stmt $add(Expr $n) { total += $n; }
  $add(5);
  return total;
}
