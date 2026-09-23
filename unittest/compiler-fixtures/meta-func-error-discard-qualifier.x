#include "x2c.x"

meta int discard_qualifier(int n) {
  const int value = n;
  Func f = %!(int &a) => a;
  return f(value);
}

int main(void) {
  (void) $discard_qualifier(1);
  return 0;
}
