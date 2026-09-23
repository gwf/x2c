#include "x2c.x"

meta int empty_arity(int n) {
  Func f = %!(int a) => a;
  return f() + n;
}

int main(void) {
  (void) $empty_arity(1);
  return 0;
}
