#include "x2c.x"
#include "meta.x"

// A loop nest folds at a constant call, on the machine. Before the loop
// variable and the cursor moved into frame slots, a `foreach` inside a
// `foreach` nested an evaluator frame per outer turn and died at about 830.
// The `foreach`/`foreach` nest here is smaller only so the fixture stays
// fast; both shapes were measured at 100,000.

$(import "meta-loop-nest.xmacro")

struct LoopRecord { int value; int last; };

int main(void) {
  int turns = 10000;
  printf("%d %d %d %d\n",
         ln_foreach_nest(10000, 3), ln_for_nest(50000, 3),
         ln_record_alias(10000), ln_record_alias(turns));
  return 0;
}
