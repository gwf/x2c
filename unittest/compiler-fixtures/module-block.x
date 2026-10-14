/* A module block splices its member's text where the block stands, so the
   unit translates as the one file it replaces. */
#include "x2c.x"
#include <stdio.h>
module int helper(int value);
module int counter;

module {
  "module-block/implementation.x",
}

int main(void) {
  printf("%d\n", helper(40) + counter);
  return 0;
}
