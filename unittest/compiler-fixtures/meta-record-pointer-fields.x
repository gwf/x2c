#include "x2c.x"

struct PointerBox { int *pointer; };
struct ConstPointerBox { const int *pointer; };
meta static int pointer_target = 5;

$(import "meta-record-pointer-fields.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d %d %d\n",
         $pointer_field_probe(0), pointer_field_probe(argc - 1),
         $pointer_qualifier_probe(0), pointer_qualifier_probe(argc - 1));
  return 0;
}
