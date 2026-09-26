#include "x2c.x"

struct NestedValue { int value; };
struct NestedBox { struct NestedValue nested; int tail; };

$(import "meta-record-inline-nested.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d %d %d\n",
         $nested_value_probe(0), nested_value_probe(argc - 1),
         $inline_record_probe(0), inline_record_probe(argc - 1));
  return 0;
}
