#include "x2c.x"

$(import "meta-iterator-protocol-adoption.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $protocol_adoption_probe(0),
         protocol_adoption_probe(argc - 1));
  printf("%d %d\n", $iter_round_trip(0), iter_round_trip(argc - 1));
  printf("%d %d\n", $fallback_counts(0), fallback_counts(argc - 1));
  return 0;
}
