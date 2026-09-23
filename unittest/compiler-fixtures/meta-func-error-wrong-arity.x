#include "x2c.x"

meta int wrong_arity(int n) {
  Func f = %!(int a) => a;
  return f(n, n);
}

int main(void) {
  (void) $wrong_arity(1);
  return 0;
}
