/*  test-autodiff.x -- dual-number family and derivative transformations */

#include "x2c.x"
#include <math.h>
#include "test-support.x"
$(import "test-macros.xmacro")
$(import "autodiff.xmacro")

typedef struct Dual { double value; double tangent; } Dual;
typedef struct Dual2 { Dual value; Dual tangent; } Dual2;
$ad.dual(Dual, dual, <dual>, double, sin, cos, exp, log, sqrt, tanh);
$ad.dual(Dual2, dual2, <dual2>, Dual,
         Dual.sin, Dual.cos, Dual.exp, Dual.log, Dual.sqrt, Dual.tanh);

static int _near(double a, double b) => fabs(a - b) < 1e-6;

static Dual _dual_mix(Dual x) {
  Dual one = 1.0;
  return x.exp().log().sqrt() * x.tanh() / (x.sin() + one) - x.cos();
}

static double _dual_mix_primal(double x) =>
  _dual_mix((Dual) { x, 0.0 }).value;

static void autodiff_dual_matches_finite_difference(void) {
  double h = 1e-6;
  Dual result = _dual_mix((Dual) { 0.7, 1.0 });
  double estimate =
    (_dual_mix_primal(0.7 + h) - _dual_mix_primal(0.7 - h)) / (2 * h);
  EXPECT_TRUE(_near(result.value, _dual_mix_primal(0.7)));
  EXPECT_TRUE(_near(result.tangent, estimate));
}

static void autodiff_dual_operators_and_converters(void) {
  Dual x = { 3.0, 1.0 };
  Dual two = 2.0;
  Dual y = x * two - x / two + -x;
  EXPECT_TRUE(_near(y.value, 6.0 - 1.5 - 3.0));
  EXPECT_TRUE(_near(y.tangent, 2.0 - 0.5 - 1.0));
  y *= 2.0;
  EXPECT_TRUE(_near(y.tangent, 2.0 * (2.0 - 0.5 - 1.0)));
  EXPECT_TRUE(x > two);
  EXPECT_TRUE(two < x);
  Var boxed = x;
  Dual back = boxed;
  EXPECT_TRUE(_near(back.value, 3.0));
}

static Dual2 _second(Dual2 x) => x.exp() * x.sin();

static void autodiff_nested_family_gives_second_derivative(void) {
  Dual2 x = { { 0.7, 1.0 }, { 1.0, 0.0 } };
  Dual2 result = _second(x);
  double expect = 2.0 * exp(0.7) * cos(0.7);
  EXPECT_TRUE(_near(result.value.value, exp(0.7) * sin(0.7)));
  EXPECT_TRUE(_near(result.tangent.tangent, expect));
}

void autodiff_suite(void) {
  $test.run(autodiff_dual_matches_finite_difference);
  $test.run(autodiff_dual_operators_and_converters);
  $test.run(autodiff_nested_family_gives_second_derivative);
}
