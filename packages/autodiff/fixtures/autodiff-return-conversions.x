#include "x2c.x"
#include "typed-array.x"
#include "autodiff-macros.x"
$ad.both()
static double integer_return(double x) { return 1; }
$ad.both()
static double integer_cast(double x) { return (int) x; }
int main(void) {
  double gradient = 99;
  double value = integer_return_grad(2, &gradient);
  printf("%.1f %.1f %.1f\n", value, gradient, integer_return_dot(2, 1));
  value = integer_cast_grad(2, &gradient);
  printf("%.1f %.1f %.1f\n", value, gradient, integer_cast_dot(2, 1));
  return 0;
}
