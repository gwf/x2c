/*  comptime-declines-meta.x -- a `meta` function that cannot be lowered

    `meta` refuses what the `$comptime()` decorator refuses, with the same
    wording. The marker is on the declaration rather than a line above it,
    so the diagnostic points there; `comptime-declines.x` owns the
    decorator's own siting. See `plans/meta-functions.md`.
*/

#include "x2c.x"

meta int mt_goto(int n) {
  if (n) goto done;
  return 1;
done:
  return 2;
}

int main(void) { return 0; }
