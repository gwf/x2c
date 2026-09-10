---
section: magic
tab: autodiff
---

```x2c
~#include "typed-array.x"
~#include <assert.h>
~#include <math.h>
$(import "autodiff.xmacro")

$ad.reverse()
static double energy(double x, double y, int n) {
  double s = 0.0;
  for (int i = 0; i < n; i++) {
    if (i == 2) continue;
    s += x * x * (double) i;
  }
  return sin(s) / x - exp(y);
}

~int main(void) {
double dx, dy;
double value = energy_grad(1.0, 2.0, 5, &dx, &dy);
~double h = 1e-6;
~double check = (energy(1.0 + h, 2.0, 5) - energy(1.0 - h, 2.0, 5)) / (2 * h);
~assert(fabs(value - energy(1.0, 2.0, 5)) < 1e-12 && fabs(dx - check) < 1e-5);
~return 0;
~}
```

`$ad.reverse()` is a decorator written in compile-time Lisp. It reads the
typed AST of `energy`, keeps the function, and emits `energy_grad` beside
it: the same computation recorded on a tape, then replayed backwards to
accumulate the derivative with respect to each `double` parameter. Loops,
branches, `break`, `continue`, and early `return` all replay exactly.
Nothing in the compiler knows about derivatives.
