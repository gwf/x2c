/*  comptime-declines.x -- what the comptime lowering pass refuses, and why

    Each function here names a construct `Compiler.lower_comptime` cannot
    lower. The diagnostic carries the reason, so this fixture checks the
    wording as well as the refusal. A phase that adds one of these constructs
    moves its function to `comptime-lowering.x`; a refusal that is a decision
    rather than a gap stays here. See
    `plans/comptime-x2c-generalization.md`.
*/

#include "x2c.x"

macro Decorator $comptime(Unit $fn) => { $(x2c.comptime.install $fn)... }

/* `goto` is refused by decision, not for want of work: the lowering has no
   place to jump to, because a lowered function is one expression per live
   local ending in a tail call. Phases that add a construct move its function
   into `comptime-lowering.x`; each deliberate refusal gets its own fixture
   with its own wording. */
$comptime()
int ct_goto(int n) {
  if (n) goto done;
  return 1;
done:
  return 2;
}

int main(void) { return 0; }
