#pragma indent
#include "x2c.x"
#include <stdio.h>

int main(void):
  int n = ({ int t = 20; t + 1; }) * 2
  printf("%d\n", n)
  return 0
