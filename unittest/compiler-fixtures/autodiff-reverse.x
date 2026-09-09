#include "x2c.x"
#include "typed-array.x"
#include <stdio.h>
#include <math.h>
$(import "autodiff.xmacro")

$ad.reverse()
static double scale(double a, double b) => a * b + exp(a);

$ad.reverse()
static double model(double x, double y, int n) {
  double s = 0.0;
  for (int i = 1; i <= n; i++) s += scale(x, y) * (double) i;
  double t = x * y + 3.0;
  if (t > 1.0) t *= t;
  else t = -t;
  int j = 0;
  while (j < 2) {
    s -= sin(t) / x;
    j++;
  }
  return t > 4.0 ? sqrt(t) + s : exp(t) - s;
}

int main(void) {
  double x_grad, y_grad;
  double value = model_grad(1.0, 2.0, 3, &x_grad, &y_grad);
  printf("%.6f %.6f %.6f\n", value, x_grad, y_grad);
  return 0;
}
