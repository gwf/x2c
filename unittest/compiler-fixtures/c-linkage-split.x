#include <stdio.h>
#include "c-linkage-split-values.h"

int scale(int value) { return value * 7; }

int main(void) {
  printf("%d\n", scale(3));
  return 0;
}
