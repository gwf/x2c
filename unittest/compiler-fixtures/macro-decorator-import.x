#include "x2c.x"

$(import "macro-decorator-import.xmacro")

$project.imported()
int imported_decorated(void) {
  return 42;
}

int main(void) {
  printf("%d\n", imported_decorated());
  return 0;
}
