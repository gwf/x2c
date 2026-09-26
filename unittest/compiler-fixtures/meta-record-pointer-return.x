#include "x2c.x"

struct BorrowedField { int value; };

$(import "meta-record-pointer-return.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $pointer_return_probe(0),
         pointer_return_probe(argc - 1));
  return 0;
}
