/* The Computer Language Benchmarks Game: binary-trees.
   Every node, including each leaf, is an ordinary two-element Array.
   Scope regions reclaim each completed tree using the runtime allocator. */

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  int maximum = argc > 1 ? atoi(argv[1]) : 10;
  if (maximum < 6) maximum = 6;
  auto {
    Array stretch = _tree(maximum + 1);
    printf("stretch tree of depth %d\t check: %ld\n",
      maximum + 1, _check(stretch));
  }
  Array long_lived = _tree(maximum);
  for (int depth = 4; depth <= maximum; depth += 2) {
    long iterations = 1L << (maximum - depth + 4), check = 0;
    for (long i = 0; i < iterations; i++)
      auto { check += _check(_tree(depth)); }
    printf("%ld\t trees of depth %d\t check: %ld\n",
      iterations, depth, check);
  }
  printf("long lived tree of depth %d\t check: %ld\n",
    maximum, _check(long_lived));
  return 0;
}

static Array _tree(int depth) {
  if (!depth) return [NULL, NULL];
  return [_tree(depth - 1), _tree(depth - 1)];
}

static long _check(Array tree) {
  if (!tree[0]) return 1;
  return 1 + _check(tree[0].array()) + _check(tree[1].array());
}
