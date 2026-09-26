#include "x2c.x"

$(import "meta-iterator-local-storage.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $local_storage_probe(0),
         local_storage_probe(argc - 1));
  return 0;
}
