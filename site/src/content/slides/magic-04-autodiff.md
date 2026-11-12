---
slug: autodiff
links:
  - label: Full source
    href: https://github.com/gwf/x2c/blob/main/packages/autodiff/examples/energy-gradient.x
  - label: Three-mode example
    href: https://github.com/gwf/x2c/blob/main/packages/autodiff/examples/autodiff.x
section: magic
home: true
order: 5
tab: autodiff
title: Differentiate the program.
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
~assert(fabs(value - energy(1.0, 2.0, 5)) < 1e-12);
~assert(fabs(dx - check) < 1e-5);
~printf("energy %.6f  d/dx %.6f  d/dy %.6f\n", value, dx, dy);
~return 0;
~}
```

Automatic differentiation transforms a function into code that computes derivatives. The example combines syntax transformation with ordinary numeric code; the linked full source includes executable checks.
