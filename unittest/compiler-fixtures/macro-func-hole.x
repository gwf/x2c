#include <stdio.h>
static Func adder;
macro Expression $m(Expr $v) => adder($v + 1, 1);
macro Expression $n(Expr $v) => adder($v, 1);
int main(void) {
  adder = %!(a, b) => (int) a + (int) b;
  int k = 5;
  printf("%d\n", (int) $n(k));
  printf("%d\n", (int) $m(5));
  return 0;
}
