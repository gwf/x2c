#include "x2c.x"
#include <stdlib.h>
#include <string.h>

extern size_t strlen(const char *text);
typedef int (*Compare)(const void *, const void *);

int main(void) {
  Func length = strlen;
  printf("%ld\n", length("abcd").integer());
  int values[2] = {2, 1};
  qsort(values, 2, sizeof(int), (Compare) (%!(const void *a, const void *b) =>
    *(const int *) a - *(const int *) b));
  printf("%d %d\n", values[0], values[1]);
  return 0;
}
