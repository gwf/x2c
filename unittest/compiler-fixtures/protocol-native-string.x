#include "x2c.x"
#include <stdio.h>

int main(void) {
  String s = %"hello";
  printf("%zu\n", s.c_len());
  return 0;
}
