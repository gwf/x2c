#include "x2c.x"

meta int null_reference(int n) {
  int *p = (int *) 0;
  Func f = %!(int &a) => a;
  return f(*p) + n;
}

int main(void) {
  (void) $null_reference(1);
  return 0;
}
