#include "x2c.x"

// A compile-time form that nests deeper than the evaluator's call budget is
// stopped and reported. Before the budget it exhausted the C stack and the
// compiler died without a word.

meta static int md_deep(int n) { return n <= 0 ? 0 : 1 + md_deep(n - 1); }

meta static List md_rows(int n) {
  Array out = [];
  for (int i = 0; i < n; i++) out.push(i);
  return out;
}

meta static int md_nest(int outer, int inner) {
  int hits = 0;
  foreach (Var a, md_rows(outer))
    foreach (Var b, md_rows(inner))
      hits = hits + 1;
  return hits;
}

int main(void) {
  printf("%d %d\n", md_deep(4000), md_nest(2000, 2));
  return 0;
}
