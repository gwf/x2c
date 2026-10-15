/* A later declaration of a file's static without `static`, at file scope
   or in a block, names that static, as C links it. */
#include <stdio.h>

module {
  "module-static-linkage/first.x",
  "module-static-linkage/second.x",
}

int main(void) {
  printf("%d %d\n", first_value(), second_value());
  return 0;
}
