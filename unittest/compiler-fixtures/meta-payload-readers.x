/* Raw payload readers return zero for the other numeric family. */
#include "x2c.x"

$(import "meta-payload-readers.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $payload_readers(0), payload_readers(argc - 1));
  return 0;
}
