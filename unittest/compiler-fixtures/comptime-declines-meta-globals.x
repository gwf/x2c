/*  comptime-declines-meta-globals.x -- file-scope state in a `meta` body

    `meta` names a function with two forms that agree. An ordinary runtime
    static has no advertised compile-time instance, so this definition is
    refused instead of treating an absent evaluator value as zero. Marked
    `meta static` values are covered by meta-globals.x.
    See `plans/meta-values-types.md`.
*/

#include "x2c.x"

static int dg_base = 10;

meta static int dg_offset(int x) => x + dg_base;

int main(void) { return 0; }
