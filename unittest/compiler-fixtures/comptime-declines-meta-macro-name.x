/*  comptime-declines-meta-macro-name.x -- a preprocessor name in `meta`

    A name the compiler never saw declared is a preprocessor macro. Apart
    from `NULL`, `true` and `false`, it has no compile-time value, and the
    refusal names it rather than calling it file-scope state.
*/

#include "x2c.x"

#define LIMIT 5

meta int dm_limit(void) { return LIMIT; }

int main(void) { return 0; }
