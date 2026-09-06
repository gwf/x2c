#include "x2c.x"

int main(void) {
  int first = 1, second = 2, *pointer = &first;
  Func change = %!() => pointer = &second;
  return 0;
}
