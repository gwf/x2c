#include "x2c.x"

$(import "meta-record-native-scalars.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $scalar_fields_probe(0),
         scalar_fields_probe(argc - 1));
  return 0;
}
