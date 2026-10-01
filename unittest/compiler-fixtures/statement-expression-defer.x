#include "x2c.x"
#include <stdio.h>

int main(void) {
  int n = ({ defer printf("done\n"); 3; });
  return n;
}
