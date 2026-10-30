#include <stdio.h>

#ifndef __cplusplus
static int chosen(void) { return 7; }
#elif defined(__cplusplus)
#include "conditional-host-unused-elif.h"
THIS IS NOT VALID X2C
#else
#include "conditional-host-unused-else.h"
THIS IS NOT VALID X2C
#endif

#if 0
THIS IS NOT VALID X2C
#else
static int alternate(void) { return 3; }
#endif

int main(void) {
  printf("%d\n", chosen() + alternate());
  return 0;
}
