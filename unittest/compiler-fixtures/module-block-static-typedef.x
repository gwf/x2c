/* Each file of a module unit keeps its own statics. Two members declare
   the same static object and static type, and one adopts its type as a
   class, whose readable name stays short. */
#include <stdio.h>

static int counter = 100;

module {
  "module-block-static-typedef/first.x",
  "module-block-static-typedef/second.x",
}

int main(void) {
  printf("%d %d %d\n", counter, first_total(), second_total());
  printf("%s\n", second_repr());
  return 0;
}
