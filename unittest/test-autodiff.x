/*  test-autodiff.x -- dual-number family and derivative transformations */

#include "x2c.x"
#include "typed-array.x"
#include "autodiff.x"
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

$ad.forward()
static double _fwd_helper(double a, int k) => pow(a, 2.0) * (double) k;

$ad.forward()
static double _fwd_mixed(double x, double y, int n) {
  double s = 0.0;
  for (int i = 1; i <= n; i++) s += _fwd_helper(x, i) / (double) i;
  double t = x * y + 3.0;
  if (t > 1.0) t *= t;
  else t = -t;
  int j = 0;
  while (j < 2) {
    s -= sin(t) / x;
    j++;
  }
  double u = t > 4.0 ? sqrt(t) : exp(t);
  return u + s - 2.0 * y + tanh(x) + log(x);
}

$ad.reverse()
static double _rev_helper(double a, double b) => a * b + sin(a);

$ad.reverse()
static double _rev_mixed(double x, double y, int n) {
  double s = 0.0;
  for (int i = 1; i <= n; i++) s += _rev_helper(x, y) * (double) i;
  double t = x * y + 3.0;
  if (t > 1.0) t *= t;
  else t = -t;
  int j = 0;
  do {
    s -= sin(t) / x;
    j++;
  } while (j < 2);
  double u = t > 4.0 ? sqrt(t) : exp(t);
  return u + s - 2.0 * y + tanh(x) + log(x);
}

static double _fwd_in_x(double x) => _fwd_mixed(x, 2.0, 3);
static double _rev_in_x(double x) => _rev_mixed(x, 2.0, 3);
static double _rev_in_y(double y) => _rev_mixed(1.0, y, 3);
static double _central(double (*f)(double), double at) {
  double h = 1e-6;
  return (f(at + h) - f(at - h)) / (2 * h);
}

static void autodiff_forward_transform_matches_finite_difference(void) {
  double tangent = _fwd_mixed_dot(1.0, 1.0, 2.0, 0.0, 3);
  EXPECT_TRUE(fabs(tangent - _central(_fwd_in_x, 1.0)) < 1e-5);
  EXPECT_TRUE(fabs(_fwd_mixed_dot(1.0, 0.0, 2.0, 1.0, 3)
                   - _central(%!(y) => _fwd_mixed(1.0, y, 3), 2.0)) < 1e-5);
}

static void autodiff_reverse_transform_matches_finite_difference(void) {
  double x_grad, y_grad;
  double value = _rev_mixed_grad(1.0, 2.0, 3, &x_grad, &y_grad);
  EXPECT_TRUE(fabs(value - _rev_mixed(1.0, 2.0, 3)) < 1e-12);
  EXPECT_TRUE(fabs(x_grad - _central(_rev_in_x, 1.0)) < 1e-5);
  EXPECT_TRUE(fabs(y_grad - _central(_rev_in_y, 2.0)) < 1e-5);
}

$ad.forward()
static double _both(double a, double b) {
  double p = 1.0;
  int k = 0;
  while (k < 3) {
    p *= a + b / (double) (k + 1);
    k++;
  }
  return p;
}

$ad.reverse()
static double _both_grad_source(double a, double b) {
  double p = 1.0;
  int k = 0;
  while (k < 3) {
    p *= a + b / (double) (k + 1);
    k++;
  }
  return p;
}

static void autodiff_forward_and_reverse_agree(void) {
  double a_grad, b_grad;
  _both_grad_source_grad(0.5, 1.5, &a_grad, &b_grad);
  EXPECT_TRUE(fabs(a_grad - _both_dot(0.5, 1.0, 1.5, 0.0)) < 1e-12);
  EXPECT_TRUE(fabs(b_grad - _both_dot(0.5, 0.0, 1.5, 1.0)) < 1e-12);
}

static double _taped(double x0, double y0, double *x_grad, double *y_grad) {
  AdTape tape = AdTape.new();
  AdNode x = tape.input(x0), y = tape.input(y0);
  AdNode s = tape.input(0.0), t = x * y + tape.input(3.0);
  AdNode limit = tape.input(100.0);
  while (t < limit) {
    s = s + t.sin() / x;
    t = t * t;
  }
  AdNode r = s - y.exp() + x.sqrt().log().tanh().cos() - (-x);
  tape.backward(r);
  if (x_grad) *x_grad = x.adjoint;
  if (y_grad) *y_grad = y.adjoint;
  return r.value;
}

static double _taped_in_x(double x) => _taped(x, 2.0, NULL, NULL);
static double _taped_in_y(double y) => _taped(1.5, y, NULL, NULL);

static void autodiff_tape_matches_finite_difference(void) {
  $test.scoped();
  double x_grad, y_grad;
  _taped(1.5, 2.0, &x_grad, &y_grad);
  EXPECT_TRUE(fabs(x_grad - _central(_taped_in_x, 1.5)) < 1e-5);
  EXPECT_TRUE(fabs(y_grad - _central(_taped_in_y, 2.0)) < 1e-5);
}

$ad.reverse()
static double _control(double x, double y, int n) {
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
    if (j > 5) break;
  } while (j < 2);
  return s * atan2(y, x) + fmax(x, y) + fmin(x, y) * log1p(x) - cbrt(y);
}

$ad.checkpoint(4)
static double _checkpointed(double x, double y, int n) {
  double s = 0.0;
  for (int i = 0; i < n; i++) {
    if (i == 1) continue;
    if (s > 40.0) break;
    s += x * x * (double) i + fabs(y) * hypot(x, y);
  }
  double t = x * y + 3.0;
  int j = 0;
  do {
    s -= sin(t) / x;
    j++;
    if (j > 5) break;
  } while (j < 2);
  return s * atan2(y, x) + fmax(x, y) + fmin(x, y) * log1p(x) - cbrt(y);
}

static double _control_in_x(double x) => _control(x, 2.0, 6);
static double _control_in_y(double y) => _control(1.0, y, 6);

static void autodiff_reverse_replays_break_continue_and_return(void) {
  double x_grad, y_grad;
  double value = _control_grad(1.0, 2.0, 6, &x_grad, &y_grad);
  EXPECT_TRUE(fabs(value - _control(1.0, 2.0, 6)) < 1e-12);
  EXPECT_TRUE(fabs(x_grad - _central(_control_in_x, 1.0)) < 1e-5);
  EXPECT_TRUE(fabs(y_grad - _central(_control_in_y, 2.0)) < 1e-5);
  /* The early return path. */
  value = _control_grad(10.0, 20.0, 6, &x_grad, &y_grad);
  EXPECT_TRUE(fabs(value - _control(10.0, 20.0, 6)) < 1e-9);
  EXPECT_TRUE(fabs(x_grad - _central(%!(x) => _control(x, 20.0, 6), 10.0))
              < 1e-3);
}

static void autodiff_checkpoint_agrees_with_full_recording(void) {
  double x_grad, y_grad, x_check, y_check;
  double value = _control_grad(1.0, 2.0, 6, &x_grad, &y_grad);
  double replay = _checkpointed_grad(1.0, 2.0, 6, &x_check, &y_check);
  EXPECT_TRUE(fabs(value - replay) < 1e-12);
  EXPECT_TRUE(fabs(x_grad - x_check) < 1e-12);
  EXPECT_TRUE(fabs(y_grad - y_check) < 1e-12);
  /* Many blocks, one snapshot each. */
  _control_grad(0.1, 0.2, 5000, &x_grad, &y_grad);
  _checkpointed_grad(0.1, 0.2, 5000, &x_check, &y_check);
  EXPECT_TRUE(fabs(x_grad - x_check) < 1e-9);
  EXPECT_TRUE(fabs(y_grad - y_check) < 1e-9);
}

static void autodiff_dual_mixed_operands_and_pow(void) {
  Dual x = { 3.0, 1.0 };
  Dual a = x * 2.0, b = 2.0 - x, c = x / 4.0 + 1.5;
  EXPECT_TRUE(_near(a.value, 6.0) && _near(a.tangent, 2.0));
  EXPECT_TRUE(_near(b.value, -1.0) && _near(b.tangent, -1.0));
  EXPECT_TRUE(_near(c.value, 2.25) && _near(c.tangent, 0.25));
  EXPECT_TRUE(x > 1.0 && !(5.0 < x));
  Dual three = 3.0;
  Dual p = x.pow(three), q = (-x).fabs();
  EXPECT_TRUE(_near(p.value, 27.0) && _near(p.tangent, 27.0));
  EXPECT_TRUE(_near(q.value, 3.0) && _near(q.tangent, 1.0));
}

void autodiff_suite(void) {
  $test.run(autodiff_dual_matches_finite_difference);
  $test.run(autodiff_dual_operators_and_converters);
  $test.run(autodiff_nested_family_gives_second_derivative);
  $test.run(autodiff_forward_transform_matches_finite_difference);
  $test.run(autodiff_reverse_transform_matches_finite_difference);
  $test.run(autodiff_forward_and_reverse_agree);
  $test.run(autodiff_tape_matches_finite_difference);
  $test.run(autodiff_reverse_replays_break_continue_and_return);
  $test.run(autodiff_checkpoint_agrees_with_full_recording);
  $test.run(autodiff_dual_mixed_operands_and_pow);
}
