/*  comptime-declines-meta-globals.x -- file-scope state in a `meta` body

    `meta` names a function with two forms that agree. These two cannot: the
    compile-time form reads the Lisp session's own table, which no unit
    initializer writes, while the emitted function reads the program's
    variable. The declaration is refused instead of returning a different
    answer at compile time.
    See `plans/meta-functions.md`.
*/

#include "x2c.x"

static int dg_base = 10;

meta static int dg_offset(int x) => x + dg_base;

int main(void) { return 0; }
