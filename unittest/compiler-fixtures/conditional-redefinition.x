/*  A variable and a function each defined in two separate conditional
    groups. x2c does not evaluate the conditions, so it cannot tell whether
    both definitions survive; it reports a redefinition only when both sit
    under the same conditional arms, and leaves this case to the C
    compiler. */

#include "x2c.x"

#define WIDE 1

#if WIDE
static int width = 2;
static int width_code(void) { return 2; }
#endif
#if !WIDE
static int width = 1;
static int width_code(void) { return 1; }
#endif

int main(void) {
  printf("%d %d\n", width, width_code());
  return 0;
}
