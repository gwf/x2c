#include "x2c.x"

/* Heap storage a meta function allocates lives in the compiler, so an
   explicit meta call cannot insert its address into the program. */

struct Node { int value; struct Node *next; };

meta struct Node *make_node(int value) {
  struct Node *node = Scope.malloc(sizeof *node);
  node->value = value;
  node->next = NULL;
  return node;
}

int main(void) {
  struct Node *node = $make_node(3);
  return node->value;
}
