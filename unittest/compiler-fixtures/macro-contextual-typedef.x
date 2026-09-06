#include "x2c.x"

typedef int macro;

macro contextual_typedef_value = 42;

int main(void) {
  printf("%d\n", contextual_typedef_value);
  return 0;
}
