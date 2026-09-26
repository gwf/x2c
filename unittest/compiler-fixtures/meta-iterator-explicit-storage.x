#include "x2c.x"

$(import "meta-iterator-explicit-storage.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $explicit_storage(0), explicit_storage(argc - 1));
  return 0;
}
