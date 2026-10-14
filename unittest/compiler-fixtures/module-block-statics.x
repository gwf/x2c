/* A `module` name is one name for every file of the unit. A `static` name
   is private to its file, so each member keeps its own `local`. */
#include <stdio.h>

module {
  "module-block-statics/first.x",
  "module-block-statics/second.x",
}

int main(void) {
  printf("%d %d %d %d\n", shared_count, doubled(), first_local(),
         second_local());
  return 0;
}
