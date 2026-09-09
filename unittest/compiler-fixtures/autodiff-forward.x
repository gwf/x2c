#include "x2c.x"
#include <stdio.h>
#include <math.h>
$(import "autodiff.xmacro")

$ad.forward()
static double scale(double a, int k) => a * (double) k;

$ad.forward()
static double model(double x, double y, int n) {
  double s = 0.0;
  for (int i = 1; i <= n; i++) s += scale(x, i) / y;
  double t = x * y + 3.0;
  if (t > 1.0) t *= t;
  else t = -t;
  return sin(t) / x - 2.0 * y + s;
}

int main(void) {
  printf("%.6f %.6f\n", model_dot(1.0, 1.0, 2.0, 0.0, 3),
         model_dot(1.0, 0.0, 2.0, 1.0, 3));
  return 0;
}
