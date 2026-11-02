#include "x2c.x"

int main(void) {
  Var value = %!(int n) => n + 1;
  value(3);
  return 0;
}
