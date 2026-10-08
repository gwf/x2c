/* match-runtime.x -- times one four-arm static match on four subjects.
   Translate it alone for the built-in lowering, or after
   `#include "match-component.x"` for the component's. */

static int classify(List value) {
  match (value) {
    case %(alpha ?x ?y): return x.int() + y.int();
    case %(beta (c ?z) *rest): return z.int() + rest.len();
    case %(gamma ?(String s)): return s.len();
    default: return 0;
  }
  return -1;
}

int main(void) {
  List a = %(alpha 1 2), b = %(beta (c 3) x y), c = %(gamma "four"),
       d = %(delta);
  long total = 0, rounds = 10000000;
  clock_t start = clock();
  for (long i = 0; i < rounds; i++)
    total += classify(a) + classify(b) + classify(c) + classify(d);
  double seconds = (double) (clock() - start) / CLOCKS_PER_SEC;
  printf("total %ld, %.1f ns per match\n", total,
         seconds * 1e9 / (4.0 * rounds));
  return 0;
}
