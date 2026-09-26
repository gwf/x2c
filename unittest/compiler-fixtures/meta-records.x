/* Adopted structs keep C value-copy and address semantics in compile-time
   execution, where each lives in native bytes. */

#include "x2c.x"

struct MetaPoint { int x; int y; };

$(import "meta-records.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $(mr_probe 3), mr_probe(argc + 2));
  return 0;
}
