#include "x2c.x"
#include "typed-array.x"
#include <assert.h>
$(import "autodiff.xmacro")

$ad.both()
static double seed(double x) { return x * x; }

$ad.forward()
static double forward_user(double x) { return seed(x) + x; }

$ad.checkpoint(2)
static double checkpoint_user(double x) {
  double y = 0.0;
  for (int i = 0; i < 3; i++) y += seed(x);
  return y;
}

/* The preceding checkpoint size and locals must not leak into this body.
   Early return in a checkpointed loop would be rejected. */
$ad.reverse()
static double reverse_user(double x) {
  double y = 0.0;
  for (int i = 0; i < 3; i++) {
    y += seed(x);
    if (i == 1) return y;
  }
  return y;
}

/* One decorator returning two reverse derivations: each template expands
   after both were built, so neither may take the other's checkpoint size
   or locals. */
meta static List ad_twin(List fn) {
  match (fn) {
    case %(function ?spec (bind (binding ?id ?name) ?rest) ?body):
      return %(function $spec (bind (binding $id ${name + "_ck"}) $rest)
                 $body);
  }
  return fn;
}

meta static List ad_both_ways(List fn) {
  List checkpointed =
    ad_checkpoint(ad_twin(fn), %(expr (int) (literal (int) "2")));
  List recorded = ad_reverse(fn);
  return %(@checkpointed @recorded);
}

macro Decorator $both_ways(Unit $fn) {
  $fn
  $ad_both_ways($fn)...
}

$both_ways()
static double twice_looped(double x) {
  double y = 0.0;
  for (int i = 0; i < 3; i++) y += x * x;
  return y;
}

int main(void) {
  double dx = 0.0;
  assert(twice_looped_grad(2.0, &dx) == 12.0 && dx == 12.0);
  assert(twice_looped_ck_grad(2.0, &dx) == 12.0 && dx == 12.0);
  assert(forward_user_dot(2.0, 1.0) == 5.0);
  assert(checkpoint_user_grad(2.0, &dx) == 12.0 && dx == 12.0);
  assert(reverse_user_grad(2.0, &dx) == 8.0 && dx == 8.0);
  return 0;
}
