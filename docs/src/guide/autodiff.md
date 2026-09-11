# Automatic Differentiation

`autodiff.xmacro` differentiates ordinary `double` code four ways:

- **Dual numbers** carry a derivative through operators at runtime.
- **`$ad.forward()`** generates a tangent function beside a decorated
  function, at compile time, from the typed AST.
- **`$ad.reverse()`** generates a gradient function the same way, recording
  a tape during the forward sweep. **`$ad.checkpoint(K)`** is the same
  gradient with the tape shrunk by a factor of about `K`.
- **`autodiff.x`** records a runtime tape for code whose shape the
  decorators cannot see.

All four are ordinary x2c: a macro file, an optional module, and the
existing protocol and decorator machinery. Nothing in the compiler knows
about derivatives.

The [runtime module reference](../library/modules/autodiff.md) documents
`AdTape` and `AdNode`. For other specialized capabilities, see
[Advanced Topics](../library/advanced-topics.md).

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
  Dual y = x * x * x - 2.0 * x;
  Dual2 z = cube((Dual2) { { 2.0, 1.0 }, { 1.0, 0.0 } });
  return y.tangent == 10.0 && z.tangent.tangent == 12.0 ? 0 : 1;
}
```

The holes are the struct type, the converter name, a fresh `Var` tag, the
scalar type, and the scalar spellings of `sin`, `cos`, `exp`, `log`,
`sqrt`, and `tanh`. Declare every struct of the family before the first
invocation. Each instantiation adopts `protocol Var`, so `+ - * /`, unary
`-`, comparisons, and dotted calls such as `x.sin()`, `x.fabs()`, and
`x.pow(y)` resolve to the generated methods. A `double` beside a dual
operand converts through the generated converter, so `2.0 * x` and
`x > 1.0` read as they would on scalars.

Each depth of nesting is a distinct C type. A derivative taken inside a
function that is itself being differentiated must use the next type in
the family; mixing a `Dual` into a `Dual2` expression is a type error.
That is a weaker guarantee than tagged perturbations give a dynamically
typed implementation: the types make an inner and an outer perturbation
distinct only when the author instantiates one type per level, and a
nested derivative written with a single `Dual` type exhibits the classic
perturbation confusion silently.

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
unary `-`, the conditional operator, the primitives listed below, and
calls to functions decorated with `$ad.forward()` earlier in the same
unit, which become calls to their `_dot` siblings. Anything else is a
diagnostic at the invocation that names the statement or expression.

The generated function is plain scalar C. Zero and unit factors are
folded at generation time, so `t_dot = x_dot * y + x * y_dot` is what
appears in the output.

## Reverse mode by transformation

`$ad.reverse()` emits `NAME_grad`. The original parameters are followed by
one `double *p_grad` per `double` parameter; the result is the primal
value, and each slot receives the partial derivative of that result. The
unit must include `typed-array.x` because the generated function records
a tape on an `ArrayDbl`:

```x2c
~#include "typed-array.x"
~#include <math.h>
$(import "autodiff.xmacro")

$ad.reverse()
static double model(double x, double y, int n) {
  double s = 0.0;
  for (int i = 0; i < n; i++) {
    if (i == 1) continue;
    if (s > 40.0) break;
    s += x * x * (double) i;
  }
  double t = x * y + 3.0;
  if (t > 100.0) return t * s;
  return sin(t) / x - 2.0 * y + s;
}

int main(void) {
  double x_grad, y_grad;
  double value = model_grad(1.0, 2.0, 6, &x_grad, &y_grad);
  return fabs(value - 9.041076) < 1e-6 && fabs(x_grad - 29.526249) < 1e-6
      && fabs(y_grad + 1.716338) < 1e-6 ? 0 : 1;
}
```

The forward sweep runs the original statements. Every assignment first
pushes the value it overwrites, an `if` pushes which branch ran, and each
loop iteration ends by pushing an exit code: zero when the body completed,
or the code of the `break` or `continue` that left it. A `return` pushes
its own code and jumps to the reverse sweep. The reverse sweep pops in
mirror order, restoring each overwritten value before accumulating the
adjoints of the assignment that produced it, so every partial derivative
is evaluated at the values the forward sweep saw. There is no renaming
into single-assignment form; restoring values makes it unnecessary.

For every exit the transformation knows statically which statements ran
before it, and it generates the reverse of exactly that prefix. A loop's
reverse pops the trip count and then, per iteration, the exit code that
selects among those prefixes. Loops nest, `do` becomes a `while` with a
first-iteration flag, and a `return` inside a loop reverses the partial
iteration and then the completed ones. Every local is hoisted to the
function head, so names must be unique within the function. `goto`,
`switch`, and assignment inside a larger expression are diagnostics.

Calls to functions decorated with `$ad.reverse()` earlier in the unit call
their `_grad` siblings, which recompute the callee's primal and return its
partials. `$ad.both()` emits both siblings; two decorators cannot stack when
each produces several items.

## Checkpointing

A recorded loop stores every overwritten value for every iteration, so tape
memory grows with the trip count. `$ad.checkpoint(K)` is `$ad.reverse()`
with every loop run twice instead: the forward sweep runs the loop without
recording and pushes a snapshot of the variables the loop assigns once
every `K` iterations; the reverse sweep restores each block from its
snapshot, replays it with recording, and reverses the replay. Tape memory
is one block's tape plus one snapshot per block, so it still grows with
the trip count, divided by `K`. `break` and `continue` replay exactly as
before; a checkpointed loop cannot contain `return`.

```x2c
~#include "typed-array.x"
~#include <math.h>
$(import "autodiff.xmacro")

$ad.checkpoint(64)
static double relax(double x, double y, int steps) {
  double s = x;
  for (int i = 0; i < steps; i++) s += 0.001 * (y - s) * cos(s * 0.01);
  return s;
}

int main(void) {
  double x_grad, y_grad;
  double value = relax_grad(1.0, 3.0, 100000, &x_grad, &y_grad);
  return fabs(value - 3.0) < 1e-9 && fabs(y_grad - 1.0) < 1e-9 ? 0 : 1;
}
```

Measured on one 2,000,000-step relaxation loop (the benchmark
`unittest/benchmarks/autodiff-checkpoint.x`, one process per variant,
Apple M-series, `-O2`):

| Variant | Peak memory | Time |
| --- | --- | --- |
| primal only | 1.6 MB | 0.033 s |
| `$ad.reverse()` | 51.5 MB | 0.053 s |
| `$ad.checkpoint(16)` | 3.6 MB | 0.068 s |
| `$ad.checkpoint(64)` | 2.1 MB | 0.065 s |
| `$ad.checkpoint(256)` | 1.8 MB | 0.066 s |
| `$ad.checkpoint(1024)` | 1.7 MB | 0.065 s |

Full recording stores three doubles per iteration; checkpointing pays about
a quarter more time for running the loop twice, and its memory is
dominated by the snapshots at small `K` and by the block tape at large
`K`.

This is two-level checkpointing with a fixed block size. The
divide-and-conquer schedule of Siskind and Pearlmutter (2018), which needs
no block size and achieves logarithmic growth, is not implemented; a
program whose loops outgrow a fixed block can nest the decorated function
in a caller that is itself decorated.

## A worked example

`examples/magic/autodiff-fit.x` fits the rate and capacity of a logistic
growth model to observations. The loss integrates the model with 4,000
Euler steps and accumulates squared residuals at ten sample times inside
the loop, so the gradient runs through a long loop with a branch in it.
The example prints the gradient beside a central finite difference, then
takes gradient-descent steps:

```text
loss 4702.386283
d/drate     -15650.816053  finite difference -15650.816049
d/dcapacity -118.848124  finite difference -118.848118
step 50  loss   2.373136  rate 0.9140  capacity 49.1688
step 100  loss   0.014606  rate 0.9016  capacity 49.9274
...
```

The parameters recover the true values 0.9 and 50 to three digits; the
remaining loss is the Euler discretization error of the model itself.

## Primitives

Both transformations differentiate calls to these `<math.h>` functions,
whose derivatives are closed forms in the same primitives:

| Family | Functions |
| --- | --- |
| Trigonometric | `sin cos tan asin acos atan atan2` |
| Hyperbolic | `sinh cosh tanh asinh acosh atanh` |
| Exponential | `exp exp2 expm1 log log2 log10 log1p pow` |
| Roots and norms | `sqrt cbrt hypot` |
| Piecewise | `fabs fmin fmax` |

`fabs`, `fmin`, and `fmax` differentiate as the branch that was taken;
at a tie the derivative follows the first argument. The dual family
provides the subset its holes name, plus `fabs` and a `pow` computed as
`exp(b log a)`, which unlike C `pow` needs a positive base.

## Runtime tape

When the shape of the computation depends on data in ways the decorators
reject, include `autodiff.x` and record it:

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
reverse, skipping callbacks whose adjoints are zero. An unused singular
operation therefore does not contaminate the requested gradient. Repeating
`backward` clears the previous adjoints before seeding the new result.
Values box through `Var` and each operation allocates a node in
the active `Scope`, so this is the slow path.

## Choosing

Use dual numbers for a few derivatives of small functions, or for
higher-order derivatives through nesting. Use `$ad.forward()` when the
generated scalar C should be readable or when the function has few inputs.
Use `$ad.reverse()` for gradients with many inputs, and
`$ad.checkpoint(K)` when its loops run long. Use the tape when the
decorators reject the code. For gradients over tensors rather than
scalars, the [torch package](torch.md) reaches libtorch's autograd
through the same operator protocols.

## Background

Forward-mode accumulation over a program's elementary operations goes
back to Wengert (1964); Baydin et al. (2018) survey the field and its
vocabulary. The transformation route follows the standard formulation of
forward and reverse mode over a program's statements (Griewank and
Walther, 2008): recording overwritten values rather than renaming into
single-assignment form is the classic tape discipline, and the exit-code
treatment of control flow makes the replay exact for `break`, `continue`,
and early `return`. Two-level checkpointing is the simplest member of the
family that Griewank (1992) made logarithmic and that Siskind and
Pearlmutter (2018) freed from user annotation.

Perturbation confusion is the failure analyzed by Siskind and Pearlmutter
(2005) and, for higher-order functions, by Manzyuk et al. (2019). The dual
family here does not tag perturbations; it offers one distinct type per
nesting level and relies on the author to use them, as described above.
The runtime tape records closures that push adjoints to their operands,
which is a Wengert tape with a closure in place of an opcode; it is in
the spirit of, but not the same construction as, the backpropagators of
Pearlmutter and Siskind (2008), which are returned functions composed
without any tape. What that line of work adds beyond this chapter,
first-class derivative operators applied to arbitrary closures with the
overhead removed by program analysis, is a compiler feature rather than a
macro and is not attempted here.

- R. E. Wengert. A simple automatic derivative evaluation program.
  *Communications of the ACM* 7(8), 1964.
- A. Griewank. Achieving logarithmic growth of temporal and spatial
  complexity in reverse automatic differentiation. *Optimization Methods
  and Software* 1(1), 1992.
- J. M. Siskind and B. A. Pearlmutter. Perturbation confusion and
  referential transparency: correct functional implementation of
  forward-mode AD. *Implementation and Application of Functional
  Languages*, 2005.
- B. A. Pearlmutter and J. M. Siskind. Reverse-mode AD in a functional
  framework: Lambda the ultimate backpropagator. *ACM Transactions on
  Programming Languages and Systems* 30(2), 2008.
- A. Griewank and A. Walther. *Evaluating Derivatives: Principles and
  Techniques of Algorithmic Differentiation*, 2nd ed. SIAM, 2008.
- A. G. Baydin, B. A. Pearlmutter, A. A. Radul, and J. M. Siskind.
  Automatic differentiation in machine learning: a survey. *Journal of
  Machine Learning Research* 18, 2018.
- J. M. Siskind and B. A. Pearlmutter. Divide-and-conquer checkpointing
  for arbitrary programs with no user annotation. *Optimization Methods
  and Software* 33(4-6), 2018.
- O. Manzyuk, B. A. Pearlmutter, A. A. Radul, D. R. Rush, and
  J. M. Siskind. Perturbation confusion in forward automatic
  differentiation of higher-order functions. *Journal of Functional
  Programming* 29, 2019.
