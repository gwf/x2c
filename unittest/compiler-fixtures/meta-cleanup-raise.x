/*  meta-cleanup-raise.x -- a cleanup runs when an error leaves its block

    The failure in `fails` leaves the `$let` block through a raise. Its
    cleanup still restores `depth`, which the next explicit call in the
    same unit observes.
*/

#include "x2c.x"
#include "meta.x"

meta static int depth = 0;

meta void fails(void) {
  $let(depth, 5) {
    x2c_diagnostic_fail("failed inside the cleanup block", %());
  }
}

meta void report(void) {
  if (depth == 0) x2c_diagnostic_fail("depth was restored", %());
  x2c_diagnostic_fail("depth was not restored", %());
}

void first(void) { $fails(); }
void second(void) { $report(); }
