#include <stdio.h>

// A lexical failure ends the token stream, so an inactive arm cannot hide
// it: the rest of the unit is missing and translation reports and fails.
#if 0
this isn't code
#endif

int main(void) {
  printf("ok\n");
  return 0;
}
