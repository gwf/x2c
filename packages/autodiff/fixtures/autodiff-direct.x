#include "x2c.x"
#include "typed-array.x"
#include <stdio.h>
#include "autodiff-macros.x"

$ad.both()
static double square(double x) => x * x;

int main(void) {
  double gradient;
  double value = square_grad(3.0, &gradient);
  printf("%.1f %.1f %.1f\n", square_dot(3.0, 1.0), value, gradient);
  return 0;
}
