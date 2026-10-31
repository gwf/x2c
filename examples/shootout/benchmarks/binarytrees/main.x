/* The Computer Language Benchmarks Game: binary-trees.
   Every node is an ordinary heap class with two child fields. Leaves allocate the
   same Node as interior nodes. One ordinary Thread runs each depth batch;
   worker-local Scope regions use the runtime allocator. */

#include <stdio.h>
#include <stdlib.h>

class Node { Node left, right; } *;
class Batch { int depth; long iterations, check; Thread worker; } *;

int main(int argc, char **argv) {
  int maximum = argc > 1 ? atoi(argv[1]) : 10;
  if (maximum < 6) maximum = 6;
  auto {
    Node stretch = _tree(maximum + 1);
    printf("stretch tree of depth %d\t check: %ld\n",
      maximum + 1, stretch.check());
  }
  Node long_lived = _tree(maximum);
  Array batches = [];
  for (int depth = 4; depth <= maximum; depth += 2)
    batches.push(Batch.new(depth, maximum));
  foreach (Batch batch in batches) {
    batch.worker.join();
    batch.worker.free();
    printf("%ld\t trees of depth %d\t check: %ld\n",
      batch.iterations, batch.depth, batch.check);
  }
  printf("long lived tree of depth %d\t check: %ld\n",
    maximum, long_lived.check());
  return 0;
}

static void Batch.init(Batch batch, int depth, int maximum) {
  batch.depth = depth;
  batch.iterations = 1L << (maximum - depth + 4);
  batch.worker = Thread.start(_check_batch, batch);
}

static Var _check_batch(Var input) {
  Batch batch = input;
  long check = 0;
  for (long i = 0; i < batch.iterations; i++)
    auto { check += _tree(batch.depth).check(); }
  batch.check = check;
  return void;
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
