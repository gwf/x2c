#include "x2c.x"

meta int wrong_value_type(int n) {
  Func f = %!(Array a) => a.len();
  return f(n);
}

int main(void) {
  (void) $wrong_value_type(1);
  return 0;
}
