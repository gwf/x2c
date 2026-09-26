#include "x2c.x"
#include "typed-array.x"
#include "typed-map.x"

$(import "meta-typed-container-conversion.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("array %s | %s\n", $packed_ints(4), packed_ints(argc + 3));
  printf("map %s | %s\n", $packed_map(2), packed_map(argc + 1));
  return 0;
}
