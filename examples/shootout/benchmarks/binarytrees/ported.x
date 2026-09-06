/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/binarytrees-ported ported.x
 *   /tmp/binarytrees-ported 12 100
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct Node *Node;
struct Node { Node left, right; int item; };

static Node _new_tree(int item, int depth) {
  Node tree = Scope.malloc(sizeof(struct Node));
  tree.item = item;
  tree.left = depth ? _new_tree(item * 2 - 1, depth - 1) : NULL;
  tree.right = depth ? _new_tree(item * 2, depth - 1) : NULL;
  return tree;
}

static int Node.sum(Node tree) {
  if (!tree.left) return tree.item;
  return tree.item + tree.left.sum() - tree.right.sum();
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int depth = atoi(argv[1]), iterations = atoi(argv[2]);
  int64_t checksum = 0;
  for (int item = 0; item < iterations; item++) {
    Scope.retain();
    checksum += _new_tree(item, depth).sum();
    Scope.release();
  }
  printf("%lld\n", (long long) checksum);
  return 0;
}
