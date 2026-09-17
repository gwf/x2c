#include "x2c.x"
#include "c-annotation-macro-values.h"

int main(void) {
  Pair pair = pair_make(3, 4);
  String name = pair_name(pair.left);
  printf("%d %s %d\n", pair_sum(pair), name, (int) name.len());
  printf("%d %d\n", pair_diff(pair), pair_max(pair));
  if (pair.left > pair.right) pair_abort(1);
  return 0;
}
