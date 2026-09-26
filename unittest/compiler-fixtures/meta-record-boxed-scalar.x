#include "x2c.x"

struct BoxedScalar { long double value; };

$(import "meta-record-boxed-scalar.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $boxed_scalar_probe(0),
         boxed_scalar_probe(argc - 1));
  return 0;
}
