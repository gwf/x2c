/* A member's macros and project `meta` functions serve the entry, as they
   would in the one file. */
#include <stdio.h>

module {
  "module-block-meta/definitions.x",
}

int main(void) {
  printf("%d %d\n", $twice(21), $table_size());
  return 0;
}
