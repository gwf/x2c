#include "x2c.x"

// A compile-time form that nests deeper than the evaluator's call budget is
// stopped and reported. Before the budget it exhausted the C stack and the
// compiler died without a word. A loop nest is not one of these: it runs on
// the machine and nests nothing, which `meta-loop-nest.x` covers.

meta static int md_deep(int n) { return n <= 0 ? 0 : 1 + md_deep(n - 1); }

int main(void) {
  printf("%d\n", $md_deep(4000));
  return 0;
}
