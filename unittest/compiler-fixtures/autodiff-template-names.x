#include "x2c.x"
#include "typed-array.x"
$(import "autodiff.xmacro")
$ad.reverse()
static inline double collide(double _ad_result) {
  double _ad_seed = _ad_result * _ad_result;
  return _ad_seed + _ad_result;
}
int main(void) { double dx; double y=collide_grad(3.0,&dx); printf("%.1f %.1f\n",y,dx); return 0; }
