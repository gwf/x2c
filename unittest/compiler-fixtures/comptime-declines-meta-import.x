/*  comptime-declines-meta-import.x -- a `meta` import that is not static

    A `meta` function in a macro import is emitted once per consuming unit,
    the way a macro family's generated statics are, so the definition must be
    `static`. `meta-import.x` owns the accepted shape. See
    `plans/meta-functions.md`.
*/

#include "x2c.x"

$(import "comptime-declines-meta-import.xmacro")

int main(void) { return 0; }
