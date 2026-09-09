// Three ways to differentiate one function: dual numbers, a forward-mode
// tangent function, and a reverse-mode gradient function.
#include "x2c.x"
#include "typed-array.x"
#include <stdio.h>
#include <math.h>
$(import "autodiff.xmacro")

typedef struct Dual { double value; double tangent; } Dual;
$ad.dual(Dual, dual, <dual>, double, sin, cos, exp, log, sqrt, tanh);

static Dual by_dual(Dual x, Dual y) {
  Dual three = 3.0;
  Dual t = x * y + three;
  if (t > three) t = t * t;
  return t.sin() / x - y.exp();
}

$ad.both()
static double energy(double x, double y) {
  double t = x * y + 3.0;
  if (t > 3.0) t *= t;
  return sin(t) / x - exp(y);
}

int main(void) {
  Dual dual = by_dual((Dual) { 1.0, 1.0 }, (Dual) { 2.0, 0.0 });
  printf("dual      f=%.6f df/dx=%.6f\n", dual.value, dual.tangent);
  printf("forward   df/dx=%.6f df/dy=%.6f\n",
         energy_dot(1.0, 1.0, 2.0, 0.0), energy_dot(1.0, 0.0, 2.0, 1.0));
  double x_grad, y_grad;
  double value = energy_grad(1.0, 2.0, &x_grad, &y_grad);
  printf("reverse   f=%.6f df/dx=%.6f df/dy=%.6f\n", value, x_grad, y_grad);
  return 0;
}
