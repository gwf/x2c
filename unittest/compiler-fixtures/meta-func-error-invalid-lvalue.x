#include "x2c.x"

meta int invalid_lvalue(int n) {
  Func f = %!(int &a) => a;
  return f(n + 1);
}

int main(void) {
  (void) $invalid_lvalue(1);
  return 0;
}
