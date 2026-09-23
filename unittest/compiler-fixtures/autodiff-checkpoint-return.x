/* A return inside a checkpointed loop is rejected; accepting it produced a
   wrong gradient. The loop body names no binding, so the reported body
   carries no binding identity. */
#include "x2c.x"
#include "typed-array.x"
$(import "autodiff.xmacro")

$ad.checkpoint(2)
static double early(double x) {
  for (int i = 0; i < 4; i++) return 1.0;
  return x;
}
