#include "x2c.x"
#include "typed-array.x"
$(import "autodiff.xmacro")

$ad.reverse()
static double jumps(double x) {
  double s = 0.0;
  if (x > 1.0) goto done;
  s = x * x;
done:
  return s;
}
