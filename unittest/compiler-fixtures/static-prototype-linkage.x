/* A function defined without `static` after a `static` prototype keeps
   internal linkage, as in C, so the header does not publish it. */
#include <stdio.h>

static int helper(void);
extern int helper(void);
int helper(void), independent(void);

int use(void) { return helper(); }

int helper(void) { return 7; }

int independent(void) { return 3; }

int main(void) {
  printf("%d\n", use());
  return 0;
}
