/*  meta-cleanup-raise.x -- a cleanup runs when an error leaves its block

    The failure in `fails` leaves the `$let` block through a raise. Its
    cleanup still restores `depth`, which the next explicit call in the
    same unit observes.
*/

#include "x2c.x"
#include "meta.x"

meta static int depth = 0;

$(import "meta-cleanup-raise.xmacro")

void first(void) { $fails(); }
void second(void) { $report(); }
