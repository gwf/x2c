#include "x2c.x"

/* Heap storage a meta function allocates lives in the compiler, so an
   explicit meta call cannot insert its address into the program. */

struct Node { int value; struct Node *next; };

$(import "meta-heap-address-result.xmacro")

int main(void) {
  struct Node *node = $make_node(3);
  return node->value;
}
