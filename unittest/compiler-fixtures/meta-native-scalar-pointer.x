#include "x2c.x"

$(import "meta-native-scalar-pointer.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $native_scalar_pointer_probe(0),
         native_scalar_pointer_probe(argc - 1));
  return 0;
}
