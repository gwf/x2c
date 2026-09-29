#include "x2c.x"

/* An address result has no compile-time value. A call at file scope leaves
   the meta build's placeholder in its declaration, which the unit's group
   declares without the initializer, so the group builds, the call reports
   its own reason, and the unit's other calls still run. */

struct Node { int value; struct Node *next; };

meta struct Node *make_node(int value) {
  struct Node *node = Scope.malloc(sizeof *node);
  node->value = value;
  node->next = NULL;
  return node;
}

meta static int one(void) => 1;

int first = $one();
int v = $make_node(3)->value;

int main(void) { return v - first; }
