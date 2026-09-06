/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/binarytrees-idiomatic main.x
 *   /tmp/binarytrees-idiomatic 12 100
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "typed-list.x"

static Var _tree(int item, int depth) {
  if (!depth) return item;
  Var left = _tree(item * 2 - 1, depth - 1);
  Var right = _tree(item * 2, depth - 1);
  List kids = %($left $right);
  return ListInt.cons(item, (ListInt) kids);
}

static int _sum(Var tree) {
  if (tree.is_integer()) return tree.int();
  ListInt node = (ListInt) tree.list();
  List kids = node.cdr();
  return node.car() + _sum(kids.car()) - _sum(kids.cadr());
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int depth = atoi(argv[1]), iterations = atoi(argv[2]);
  int64_t checksum = 0;
  for (int item = 0; item < iterations; item++) {
    List.pool_retain();
    checksum += _sum(_tree(item, depth));
    List.pool_release();
  }
  printf("%lld\n", (long long) checksum);
  return 0;
}
