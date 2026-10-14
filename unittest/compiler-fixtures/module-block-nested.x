/* A member may hold its own block, whose members lie under the member's
   companion directory. A member's include of a file beside it reaches that
   file. */
#include <stdio.h>
module int base = 10;

module {
  "module-block-nested/inner.x",
}

int main(void) {
  printf("%d\n", inner_total());
  return 0;
}
