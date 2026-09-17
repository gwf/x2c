#include "c-linkage-values-include.h"

#ifdef __cplusplus
extern "C" {
#endif
#if 0
} /* unconfuse editors */
#endif
#include <stdio.h>

int scale(int value);

#ifdef __cplusplus
}
#endif

int scale(int value) { return value * unit; }

int main(void) {
  printf("%d\n", scale(3));
  return 0;
}
