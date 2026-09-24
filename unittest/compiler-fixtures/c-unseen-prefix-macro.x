#include <stdio.h>
#include "c-unseen-prefix-macro-values.h"

int unit = 7;

int scale(int value) { return value * unit; }

int main(void) {
  printf("%d\n", scale(3));
  return 0;
}
