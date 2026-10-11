/* A member's statics are visible to later members and to the entry after
   the block. */
#include <stdio.h>

module {
  "module-block-statics/first.x",
  "module-block-statics/second.x",
}

int main(void) {
  printf("%d %d\n", shared_count, doubled());
  return 0;
}
