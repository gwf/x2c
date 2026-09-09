#include "x2c.x"
#include "typed-array.x"
#include <stdio.h>
#include <math.h>
$(import "autodiff.xmacro")

$ad.reverse()
static double walk(double x, double y, int n) {
  double s = 0.0;
  for (int i = 0; i < n; i++) {
    if (i == 1) continue;
    if (s > 40.0) break;
    s += x * x * (double) i + fabs(y) * hypot(x, y);
  }
  double t = x * y + 3.0;
  if (t > 100.0) return t * s;
  int j = 0;
  do {
    s -= sin(t) / x;
    j++;
  } while (j < 2);
  return s * atan2(y, x) + fmax(x, y);
}

$ad.checkpoint(4)
static double replay(double x, double y, int n) {
  double s = 0.0;
  for (int i = 0; i < n; i++) {
    if (i == 1) continue;
    s += x * x * (double) i + fabs(y) * hypot(x, y);
  }
  return s * atan2(y, x);
}

int main(void) {
  double x_grad, y_grad;
  double value = walk_grad(1.0, 2.0, 6, &x_grad, &y_grad);
  printf("%.6f %.6f %.6f\n", value, x_grad, y_grad);
  value = walk_grad(10.0, 20.0, 6, &x_grad, &y_grad);
  printf("%.6f %.6f %.6f\n", value, x_grad, y_grad);
  value = replay_grad(1.0, 2.0, 9, &x_grad, &y_grad);
  printf("%.6f %.6f %.6f\n", value, x_grad, y_grad);
  return 0;
}
