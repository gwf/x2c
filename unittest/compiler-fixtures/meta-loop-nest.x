#include "x2c.x"
#include "meta.x"

// A loop nest folds at a constant call, on the machine. Before the loop
// variable and the cursor moved into frame slots, a `foreach` inside a
// `foreach` nested an evaluator frame per outer turn and died at about 830.
// The `foreach`/`foreach` nest here is smaller only so the fixture stays
// fast; both shapes were measured at 100,000.

meta static List ln_rows(int n) {
  Array out = [];
  for (int i = 0; i < n; i++) out.push(i);
  return out;
}

meta static int ln_foreach_nest(int outer, int inner) {
  int hits = 0;
  List xs = ln_rows(inner);
  foreach (Var a, ln_rows(outer))
    foreach (Var b, xs)
      hits = hits + 1;
  return hits;
}

meta static int ln_for_nest(int outer, int inner) {
  int hits = 0;
  List xs = ln_rows(inner);
  for (int k = 0; k < outer; k++)
    foreach (Var b, xs)
      hits = hits + 1;
  return hits;
}

struct LoopRecord { int value; int last; };

/* A marked source function owns this record and addressed field for the
   whole call.  The prepared loop Lambda must reuse that owner without
   bypassing the source-function boundary or recursively interpreting every
   turn. */
meta static int ln_record_alias(int turns) {
  struct LoopRecord state = { .value = 1, .last = 0 };
  int *field = &state.value;
  for (int i = 0; i < turns; i++) {
    state.value += 1;
    *field += 1;
    state.last = i;
  }
  return state.value + *field + state.last;
}

int main(void) {
  int turns = 10000;
  printf("%d %d %d %d\n",
         ln_foreach_nest(10000, 3), ln_for_nest(50000, 3),
         ln_record_alias(10000), ln_record_alias(turns));
  return 0;
}
