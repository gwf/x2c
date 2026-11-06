// Differentiate a loop with a continue in reverse mode, then check the
// gradient against a central finite difference.
#include <assert.h>
#include <math.h>
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

int main(void) {
  double dx, dy;
  double value = energy_grad(1.0, 2.0, 5, &dx, &dy);
  double h = 1e-6;
  double check = (energy(1.0 + h, 2.0, 5) - energy(1.0 - h, 2.0, 5)) / (2 * h);
  assert(fabs(value - energy(1.0, 2.0, 5)) < 1e-12);
  assert(fabs(dx - check) < 1e-5);
  printf("energy %.6f  d/dx %.6f  d/dy %.6f\n", value, dx, dy);
  return 0;
}
