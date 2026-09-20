#include "x2c.x"
#include "typed-array.x"
#include <assert.h>
$(import "autodiff.xmacro")

$ad.both()
static double post_inc(double x) { x++; return x * x; }
$ad.both()
static double pre_inc(double x) { ++x; return x * x; }
$ad.both()
static double post_dec(double x) { x--; return x * x; }
$ad.both()
static double pre_dec(double x) { --x; return x * x; }

int main(void) {
  double dx;
  assert(post_inc_grad(2.0, &dx) == 9.0 && dx == 6.0);
  assert(pre_inc_grad(2.0, &dx) == 9.0 && dx == 6.0);
  assert(post_dec_grad(2.0, &dx) == 1.0 && dx == 2.0);
  assert(pre_dec_grad(2.0, &dx) == 1.0 && dx == 2.0);
  assert(post_inc_dot(2.0, 1.0) == 6.0);
  assert(pre_inc_dot(2.0, 1.0) == 6.0);
  assert(post_dec_dot(2.0, 1.0) == 2.0);
  assert(pre_dec_dot(2.0, 1.0) == 2.0);
  return 0;
}
