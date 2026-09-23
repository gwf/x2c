#include "x2c.x"

meta int concrete_void(int n) {
  Func f = %!(int a) => a;
  return f(void) + n;
}

int main(void) {
  (void) $concrete_void(1);
  return 0;
}
