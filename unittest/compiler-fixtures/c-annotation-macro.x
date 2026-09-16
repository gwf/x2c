#include "x2c.x"
#include "c-annotation-macro-values.h"

int main(void) {
  Pair pair = pair_make(3, 4);
  String name = pair_name(pair.left);
  printf("%d %s %d\n", pair_sum(pair), name, (int) name.len());
  return 0;
}
