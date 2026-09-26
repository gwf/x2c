#include "x2c.x"

meta int maybe(int &?value) {
  if (!value) return 0;
  value += 2;
  return value;
}

meta int forward(int &?value) {
  Func function = maybe;
  return function(value).int();
}

meta int exercise(int n) {
  int value = n;
  Func function = maybe;
  int result = function(value).int();
  if (forward(NULL) != 0) return -1;
  return result * 10 + function(NULL).int();
}

int main(void) { return $exercise(3) != 50; }
