#include "x2c.x"

int main(void) {
  const int value = 1;
  int other = 2;
  Func change = %!() using &value, &other => {
    (value, other) = %(3 4);
    return value;
  };
  (void) change;
  return 0;
}
