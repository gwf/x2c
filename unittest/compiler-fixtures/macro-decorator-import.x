#include "x2c.x"

#include "macro-decorator-import-defs.x"

$project.imported()
int imported_decorated(void) {
  return 42;
}

int main(void) {
  printf("%d\n", imported_decorated());
  return 0;
}
