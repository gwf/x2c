# Automatic Differentiation

`autodiff.xmacro` differentiates ordinary `double` code three ways. Dual
numbers carry a derivative through operators at runtime. The two decorators
generate a sibling function at compile time from the typed AST: a tangent
function for forward mode and a gradient function for reverse mode. The
optional `autodiff.x` module records a runtime tape for code the decorators
do not accept.

## Dual numbers

Declare a struct with `value` and `tangent` fields and let `$ad.dual`
generate its arithmetic. The scalar type and the primitives it lifts are
holes, so the same family nests:

```x2c
~#include <math.h>
$(import "autodiff.xmacro")

typedef struct Dual { double value; double tangent; } Dual;
typedef struct Dual2 { Dual value; Dual tangent; } Dual2;

$ad.dual(Dual, dual, <dual>, double, sin, cos, exp, log, sqrt, tanh);
$ad.dual(Dual2, dual2, <dual2>, Dual,
         Dual.sin, Dual.cos, Dual.exp, Dual.log, Dual.sqrt, Dual.tanh);

static Dual2 cube(Dual2 x) => x * x * x;

int main(void) {
  Dual x = { 2.0, 1.0 };
  Dual y = x * x * x;
  Dual2 z = cube((Dual2) { { 2.0, 1.0 }, { 1.0, 0.0 } });
  return y.tangent == 12.0 && z.tangent.tangent == 12.0 ? 0 : 1;
}
```

The holes are the struct type, the converter name, a fresh `Var` tag, the
scalar type, and the scalar spellings of `sin`, `cos`, `exp`, `log`,
`sqrt`, and `tanh`. Declare every struct of the family before the first
invocation; the generated public prototypes precede any later typedef in
the unit's header. Each instantiation adopts `protocol Var`, so `+ - * /`,
unary `-`, comparisons, and dotted calls such as `x.sin()` resolve to the
generated methods. `Dual two = 2.0;` and `x *= 2.0` convert through the
generated `double.dual` converter; a binary operator does not convert its
operands, so write the constant as a `Dual` first.

Each depth of nesting is a distinct C type. A derivative taken inside a
function that is itself being differentiated uses the next type in the
family, which is what keeps an inner perturbation from being confused with
an outer one.

## Forward mode by transformation

`$ad.forward()` decorates a file-scope function that returns `double` and
emits `NAME_dot` beside it. Every `double` parameter `p` is followed by a
tangent parameter `p_dot`, and the result is the directional derivative:

```x2c
~#include <math.h>
$(import "autodiff.xmacro")

$ad.forward()
static double scale(double a, int k) => a * (double) k;

$ad.forward()
static double model(double x, double y, int n) {
  double s = 0.0;
  for (int i = 1; i <= n; i++) s += scale(x, i) / y;
  double t = x * y + 3.0;
  if (t > 1.0) t *= t;
  else t = -t;
  return sin(t) / x - 2.0 * y + s;
}

int main(void) {
  double df_dx = model_dot(1.0, 1.0, 2.0, 0.0, 3);
  double df_dy = model_dot(1.0, 0.0, 2.0, 1.0, 3);
  return df_dx > 22.9 && df_dx < 23.0 && df_dy > 6.4 && df_dy < 6.5 ? 0 : 1;
}
```

The transformation reads the typed AST. `double` parameters and plain
`double` locals carry tangents; other `double` expressions are constants,
and `int` control flow is copied unchanged. Supported statements are
declarations, assignment including compound assignment and increments,
`if`, `while`, `do`, `for`, `break`, `continue`, and `return`. Supported
expressions are literals, identifiers, parentheses, casts, `+ - * /`,
unary `-`, the conditional operator, the primitives `sin cos tan exp log
sqrt sinh cosh tanh atan pow`, and calls to functions decorated with
`$ad.forward()` earlier in the same unit, which become calls to their
`_dot` siblings. Anything else is a diagnostic at the invocation that
names the statement or expression.

## Reverse mode by transformation

`$ad.reverse()` emits `NAME_grad`. The original parameters are followed by
one `double *p_grad` per `double` parameter; the result is the primal
value, and each slot receives the partial derivative of that result. The
unit includes `typed-array.x` because the generated function records a
tape on an `ArrayDbl`:

```x2c
~#include "typed-array.x"
~#include <math.h>
$(import "autodiff.xmacro")

$ad.reverse()
static double model(double x, double y, int n) {
  double s = 0.0;
  for (int i = 1; i <= n; i++) s += x * x * (double) i;
  double t = x * y + 3.0;
  if (t > 1.0) t *= t;
  return sin(t) / x - 2.0 * y + s;
}

int main(void) {
  double x_grad, y_grad;
  double value = model_grad(1.0, 2.0, 3, &x_grad, &y_grad);
  return value < 0.0 && x_grad > 32.0 && y_grad < 0.0 ? 0 : 1;
}
```

The forward sweep runs the original statements and pushes each overwritten
value and each branch decision; the reverse sweep pops them back, so every
adjoint reads the values the forward sweep saw, and loops replay by their
trip count. Every local is hoisted to the function head, so names must be
unique within the function, `return` must end the body, and `break` and
`continue` are diagnostics. Calls to functions decorated with
`$ad.reverse()` earlier in the unit call their `_grad` siblings.

`$ad.both()` emits both siblings; two decorators cannot stack when each
produces several items.

## Runtime tape

When the shape of the computation depends on data, include `autodiff.x`
and record it:

```x2c
~#include "autodiff.x"
int main(void) {
  AdTape tape = AdTape.new();
  AdNode x = tape.input(1.5), y = tape.input(2.0);
  AdNode t = x * y, limit = tape.input(100.0);
  while (t < limit) t = t * t;
  AdNode r = t.log() - y.exp();
  tape.backward(r);
  return x.adjoint > 0.0 && y.adjoint < 0.0 ? 0 : 1;
}
```

Every operation records a closure that propagates its adjoint to its
operands; `AdTape.backward` seeds the result and replays the tape in
reverse. Values box through `Var` and each operation allocates a node in
the active `Scope`, so this is the slow path.

## Choosing

Use dual numbers for a few derivatives of small functions with no build
step beyond the macro. Use `$ad.forward()` when generated scalar C should
be readable or when many directional derivatives are needed. Use
`$ad.reverse()` for gradients with many inputs. Use the tape when the
decorators reject the code.
