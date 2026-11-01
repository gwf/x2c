int main(void) {
  int value = expand %(1 2) macro Expression(Expr $n) => $n;
  return value;
}
