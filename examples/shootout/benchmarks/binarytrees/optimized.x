/* The Computer Language Benchmarks Game: binary-trees.
   A heap class stores two typed child handles per node. Leaves allocate the
   same Node as interior nodes. Scope regions use the runtime allocator. */

#include <stdio.h>
#include <stdlib.h>

class Node { Node left, right; } *;

int main(int argc, char **argv) {
  int maximum = argc > 1 ? atoi(argv[1]) : 10;
  if (maximum < 6) maximum = 6;
  auto {
    Node stretch = _tree(maximum + 1);
    printf("stretch tree of depth %d\t check: %ld\n",
      maximum + 1, stretch.check());
  }
  Node long_lived = _tree(maximum);
  for (int depth = 4; depth <= maximum; depth += 2) {
    long iterations = 1L << (maximum - depth + 4), check = 0;
    for (long i = 0; i < iterations; i++)
      auto { check += _tree(depth).check(); }
    printf("%ld\t trees of depth %d\t check: %ld\n",
      iterations, depth, check);
  }
  printf("long lived tree of depth %d\t check: %ld\n",
    maximum, long_lived.check());
  return 0;
}

static void Node.init(Node tree, Node left, Node right) {
  tree.left = left;
  tree.right = right;
}

static Node _tree(int depth) {
  if (!depth) return Node.new(NULL, NULL);
  return Node.new(_tree(depth - 1), _tree(depth - 1));
}

static long Node.check(Node tree) =>
  tree.left ? 1 + tree.left.check() + tree.right.check() : 1;
