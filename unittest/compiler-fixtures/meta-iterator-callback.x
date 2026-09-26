#include "x2c.x"

$(import "meta-iterator-callback.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $iterator_callback_probe(0),
         iterator_callback_probe(argc - 1));
  return 0;
}
