/* A case label may not enter the region a defer opened in its switch. */

#include "x2c.x"

#include <stdlib.h>

static void choose(int k) {
  switch (k) {
  case 0:;
    int *p = malloc(sizeof(int));
    defer free(p);
    p[0] = k;
  case 1:
    k++;
  }
}

int main(void) {
  choose(1);
  return 0;
}
