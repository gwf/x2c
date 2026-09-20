/*  comptime-autodiff.x -- production meta autodiff, finite-difference checks

    The shared implementation is in lib/autodiff.xmacro. General lowering
    coverage stays in comptime-lowering and meta-differential.
*/

#include "x2c.x"
#include "typed-array.x"
#include <math.h>
$(import "autodiff.xmacro")

$ad.forward()
static double square(double x) {
  double y = x * x;
  return y + x;
}

$ad.forward()
static double poly(double x) {
  double acc = 0.0;
  double term = x * x * x;
  acc = term + x * x;
  return acc + x;
}

$ad.forward()
static double mixed(double x) {
  double a = sin(x) * exp(x);
  double b = sqrt(x) + log(x);
  return a + b + pow(x, 3.0) + fabs(x) + atan2(x, 2.0);
}

$ad.reverse()
static double energy(double x, double y) {
  double a = x * y;
  double b = sin(x) + a * a;
  return b / (1.0 + y * y);
}

$ad.reverse()
static double horner(double x, double y) {
  double acc = 0.0;
  for (int i = 0; i < 4; i++) {
    acc = acc * x + y;
    if (i == 2) acc = acc * acc;
  }
  return acc;
}

$ad.reverse()
static double guarded(double x, double y) {
  double acc = 1.0;
  int i = 0;
  while (i < 6) {
    i = i + 1;
    if (i == 2) continue;
    if (i == 5) break;
    acc = acc * (x + y * acc);
  }
  return acc;
}

/* Printing a tolerance verdict rather than the digits keeps the expectation
   stable across platforms. */
static int failures = 0;

static void check(const char *what, double got, double expected) {
  double scale = fabs(expected) > 1.0 ? fabs(expected) : 1.0;
  if (fabs(got - expected) / scale < 1e-6) printf("ok   %s\n", what);
  else {
    printf("FAIL %s got %.9f expected %.9f\n", what, got, expected);
    failures++;
  }
}

int main(void) {
  double e = 1e-6, gx = 0.0, gy = 0.0;

  check("square_dot", square_dot(3.0, 1.0), 7.0);
  check("poly_dot", poly_dot(2.0, 1.0), 17.0);

  energy_grad(1.1, 0.7, &gx, &gy);
  check("energy_grad/x", gx, (energy(1.1 + e, 0.7) - energy(1.1 - e, 0.7)) / (2.0 * e));
  check("energy_grad/y", gy, (energy(1.1, 0.7 + e) - energy(1.1, 0.7 - e)) / (2.0 * e));

  horner_grad(0.9, 1.2, &gx, &gy);
  check("horner_grad/x", gx, (horner(0.9 + e, 1.2) - horner(0.9 - e, 1.2)) / (2.0 * e));
  check("horner_grad/y", gy, (horner(0.9, 1.2 + e) - horner(0.9, 1.2 - e)) / (2.0 * e));

  guarded_grad(0.8, 0.3, &gx, &gy);
  check("guarded_grad/x", gx, (guarded(0.8 + e, 0.3) - guarded(0.8 - e, 0.3)) / (2.0 * e));
  check("guarded_grad/y", gy, (guarded(0.8, 0.3 + e) - guarded(0.8, 0.3 - e)) / (2.0 * e));

  check("mixed_dot", mixed_dot(1.3, 1.0),
        (mixed(1.3 + e) - mixed(1.3 - e)) / (2.0 * e));

  printf(failures ? "FAILURES %d\n" : "all derivatives match\n", failures);
  return failures != 0;
}
