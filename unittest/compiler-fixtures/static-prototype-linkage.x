/* A function defined without `static` after a `static` prototype keeps
   internal linkage, as in C, so the header does not publish it. */
#include <stdio.h>

static int helper(void);

int use(void) { return helper(); }

int helper(void) { return 7; }

int main(void) {
  printf("%d\n", use());
  return 0;
}
