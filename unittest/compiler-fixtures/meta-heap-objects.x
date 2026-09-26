#include "x2c.x"

/* Meta code builds structs on the Scope heap; each line prints the
   compile-time answer beside the native one. */

struct Node { int value; struct Node *next; };
struct Pair { short a; double b; };
struct Mixed { char tag; long count; unsigned char on; };

meta long layout_sizes(void) {
  struct Pair pair;
  return sizeof(char) + sizeof(short) * 10 + sizeof(int) * 100 +
         sizeof(void *) * 1000 + sizeof(struct Mixed) * 10000 +
         sizeof pair * 100000;
}

meta struct Node *push_node(struct Node *head, int value) {
  struct Node *node = Scope.malloc(sizeof *node);
  node->value = value;
  node.next = head;
  return node;
}

meta long list_sum(int count) {
  struct Node *head = NULL;
  for (int i = 1; i <= count; i++) head = push_node(head, i);
  long total = 0;
  for (struct Node *at = head; at; at = at->next) total += at->value;
  while (head) {
    struct Node *next = head->next;
    Scope.free(head);
    head = next;
  }
  return total;
}

meta double pair_sum(int count) {
  struct Pair *pairs = Scope.calloc(count, sizeof(struct Pair));
  for (int i = 0; i < count; i++) {
    pairs[i].a = i;
    (pairs + i)->b = i * 0.5;
  }
  pairs = Scope.realloc(pairs, 2 * count * sizeof *pairs);
  for (int i = count; i < 2 * count; i++) {
    struct Pair *at = &pairs[i];
    at->a = i;
    at->b = 1;
  }
  double total = 0;
  for (struct Pair *at = pairs + 2 * count - 1; at >= pairs; at = at - 1)
    total += at->a + at->b;
  Scope.free(pairs);
  return total;
}

meta int copied_bytes(void) {
  int values[3] = {4, 5, 6};
  int *copy = Scope.memdup(values, sizeof values[0] * 3);
  int result = copy[0] * 100 + copy[1] * 10 + *(copy + 2);
  Scope.free(copy);
  return result;
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%ld %ld\n", $layout_sizes(), layout_sizes());
  printf("%ld %ld\n", $list_sum(10), list_sum(9 + argc));
  printf("%g %g\n", $pair_sum(4), pair_sum(3 + argc));
  printf("%d %d\n", $copied_bytes(), copied_bytes());
  return 0;
}
