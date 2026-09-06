/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/binarytrees-idiomatic main.x
 *   /tmp/binarytrees-idiomatic 12 100
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static Var _tree(int item, int depth) {
  if (!depth) return item;
  Var left = _tree(item * 2 - 1, depth - 1);
  Var right = _tree(item * 2, depth - 1);
  return %[$item, $left, $right];
}

static int _sum(Var tree) {
  if (tree.is_integer()) return tree.int();
  Array node = tree.array();
  return node[0].int() + _sum(node[1]) - _sum(node[2]);
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int depth = atoi(argv[1]), iterations = atoi(argv[2]);
  int64_t checksum = 0;
  for (int item = 0; item < iterations; item++) {
    Scope.retain();
    checksum += _sum(_tree(item, depth));
    Scope.release();
  }
  printf("%lld\n", (long long) checksum);
  return 0;
}
