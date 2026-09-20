/*  comptime-declines-defer.x -- why `defer` is refused at compile time

    A refusal stops translation at the first function, so each deliberate
    decline needs its own fixture. This one checks the wording for `defer`;
    see `plans/comptime-x2c-generalization.md`.
*/

#include "x2c.x"

/* `Array a = []; defer a.free();` is correct x2c and wrong compile-time
   x2c. The evaluator owns every value a compile-time function makes, so
   freeing one would take the value out from under it. The refusal names
   `defer` rather than the operation the deferred statement calls. */
meta int ct_defer(int n) {
  Array a = [];
  defer a.free();
  a.push(n);
  return (int) a.len();
}

int main(void) { return 0; }
