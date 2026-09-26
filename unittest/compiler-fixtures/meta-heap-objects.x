#include "x2c.x"

/* Meta code builds structs on the Scope heap; each line prints the
   compile-time answer beside the native one. */

struct Node { int value; struct Node *next; };
struct Pair { short a; double b; };
struct Mixed { char tag; long count; unsigned char on; };

$(import "meta-heap-objects.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%ld %ld\n", $layout_sizes(), layout_sizes());
  printf("%ld %ld\n", $list_sum(10), list_sum(9 + argc));
  printf("%g %g\n", $pair_sum(4), pair_sum(3 + argc));
  printf("%d %d\n", $copied_bytes(), copied_bytes());
  return 0;
}
