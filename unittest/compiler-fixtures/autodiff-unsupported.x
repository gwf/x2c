#include "x2c.x"
#include "typed-array.x"
$(import "autodiff.xmacro")

$ad.reverse()
static double stops_early(double x) {
  double s = 0.0;
  for (int i = 0; i < 4; i++) {
    if (s > 1.0) break;
    s += x;
  }
  return s;
}
