#include "x2c.x"
macro Expression $half(Expr $value) => $value.len() / 2;
int main(void) {
  int n = 7;
  printf("%d\n", $half(n));
  return 0;
}
