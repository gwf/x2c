#include "x2c.x"

meta int change_pointee(int n) {
  int *p = &n;
  Func f = %!(const int *&a) => *a;
  return f(p);
}

int main(void) {
  (void) $change_pointee(1);
  return 0;
}
