#include "x2c.x"

struct CallValue { int value; int *borrowed; };

$(import "meta-record-call-values.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $call_value_probe(0),
         call_value_probe(argc - 1));
  return 0;
}
