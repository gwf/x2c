---
slug: autodiff
links:
  - label: Full source
    href: https://github.com/gwf/x2c/blob/main/packages/autodiff/examples/energy-gradient.x
  - label: Three-mode example
    href: https://github.com/gwf/x2c/blob/main/packages/autodiff/examples/autodiff.x
section: magic
home: true
order: 8
tab: autodiff
title: Derive me crazy.
run: |
  make -C packages/autodiff builds/example-energy-gradient
  ./packages/autodiff/builds/example-energy-gradient
---

<!-- ignore: requires the linked package. -->
```x2c,ignore
~#include <assert.h>
~#include <math.h>
import "autodiff";

$ad.reverse()
static double energy(double x, double y, int n) {
  double s = 0.0;
  for (int i = 0; i < n; i++) {
    if (i == 2)
      continue;
    s += x * x * (double) i;
  }
  return sin(s) / x - exp(y);
}

~int main(void) {
double dx, dy;
double value = energy_grad(1.0, 2.0, 5, &dx, &dy);
~double h = 1e-6;
~double check = (energy(1.0 + h, 2.0, 5) - energy(1.0 - h, 2.0, 5)) / (2 * h);
~assert(fabs(value - energy(1.0, 2.0, 5)) < 1e-12);
~assert(fabs(dx - check) < 1e-5);
~printf("energy %.6f  d/dx %.6f  d/dy %.6f\n", value, dx, dy);
~return 0;
~}
```

At compile time, `$ad.reverse()` transforms this function into `energy_grad`: native code that computes the value and both partial derivatives. The transformation handles the loop, branch, and mathematical operations together. Write the calculation once; the package generates its derivative code. The complete example checks the result against a finite difference.
