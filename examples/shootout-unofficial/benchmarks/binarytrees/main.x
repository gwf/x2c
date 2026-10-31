/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/binarytrees-idiomatic main.x
 *   /tmp/binarytrees-idiomatic 12 100
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct Node *Node;
struct Node { int item; Var left, right; };

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int depth = atoi(argv[1]), iterations = atoi(argv[2]);
  int64_t checksum = 0;
  for (int item = 0; item < iterations; item++) auto {
    checksum += _sum(_tree(item, depth));
  }
  printf("%lld\n", (long long) checksum);
  return 0;
}

static Var _tree(int item, int depth) {
  if (!depth) return item;
  Var left = _tree(item * 2 - 1, depth - 1);
  Var right = _tree(item * 2, depth - 1);
  Node node = xmalloc(sizeof(struct Node));
  *node = (struct Node) {item, left, right};
  Var result = (void *) node;
  return result;
}

static int _sum(Var tree) {
  if (tree.is_integer()) return tree.int();
  Node node = tree.pointer();
  return node.item + _sum(node.left) - _sum(node.right);
}
