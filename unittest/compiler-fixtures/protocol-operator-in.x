#include "x2c.x"
#include <stdio.h>

int main(void) {
  Array values = %[1, 2, 3];
  printf("%d %d\n", 2 in values, 9 in values);
  return 0;
}
