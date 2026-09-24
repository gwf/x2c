#include "x2c.x"

meta int wrong_reference_type(int n) {
  unsigned value = n;
  Func f = %!(int &a) => a;
  return f(value);
}

int main(void) {
  (void) $wrong_reference_type(1);
  return 0;
}
