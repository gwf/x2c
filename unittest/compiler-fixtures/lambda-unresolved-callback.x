#include "x2c.x"
#include <stdlib.h>

int main(void) {
  int values[2] = {2, 1};
  qsort(values, 2, sizeof(int), %!(const void *a, const void *b) =>
    *(const int *) a - *(const int *) b);
  return 0;
}
