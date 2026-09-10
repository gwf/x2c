---
slug: autodiff
section: magic
tab: autodiff
title: Fit a growth curve.
---

```x2c
~// Fit the two parameters of a logistic growth model to observations by
~// gradient descent. The loss integrates the model with 4000 Euler steps and
~// compares it with the observed curve along the way, so its gradient runs
~// through a long loop with a branch inside; $ad.checkpoint keeps the tape
~// small by replaying the loop in blocks of 64 steps.
~#include "x2c.x"
~#include "typed-array.x"
~#include <stdio.h>
~#include <math.h>
$(import "autodiff.xmacro")

~// The observations come from the same model with rate 0.9 and capacity 50.
~static double observed(double t) => 50.0 / (1.0 + 49.0 * exp(-0.9 * t));
~
$ad.checkpoint(64)
static double loss(double rate, double capacity) {
  double p = 1.0, t = 0.0, sum = 0.0;
  for (int step = 0; step < 4000; step++) {
    p += 0.0025 * rate * p * (1.0 - p / capacity);
    t += 0.0025;
    if (step % 400 == 399) {
      double residual = p - 50.0 / (1.0 + 49.0 * exp(-0.9 * t));
      sum += residual * residual;
    }
  }
  return sum;
}

int main(void) {
  double rate = 0.5, capacity = 30.0, d_rate, d_capacity, h = 1e-6;
  double value = loss_grad(rate, capacity, &d_rate, &d_capacity);
~  printf("loss %.6f\n", value);
~  printf("d/drate     %.6f  finite difference %.6f\n", d_rate,
~         (loss(rate + h, capacity) - loss(rate - h, capacity)) / (2 * h));
~  printf("d/dcapacity %.6f  finite difference %.6f\n", d_capacity,
~         (loss(rate, capacity + h) - loss(rate, capacity - h)) / (2 * h));
  for (int i = 1; i <= 200; i++) {
    value = loss_grad(rate, capacity, &d_rate, &d_capacity);
    rate -= 1e-5 * d_rate;
    capacity -= 1e-2 * d_capacity;
    if (i % 50 == 0)
      printf("step %2d  loss %10.6f  rate %.4f  capacity %.4f\n",
             i, value, rate, capacity);
  }
~  printf("observed(4) %.4f  model(4) %.4f\n", observed(4.0),
~         capacity / (1.0 + (capacity - 1.0) * exp(-rate * 4.0)));
  return 0;
}
```

Fit a growth model to observations by adjusting its growth rate and maximum
population. The `loss` function simulates the population over 4,000 small
time steps and measures its squared error at ten observation points. This
example generates those observations from a known model, so there is a
specific answer to recover: a rate of 0.9 and a capacity of 50.

`$ad.checkpoint(64)` is a decorator written in compile-time Lisp. It reads
the typed syntax tree and generates `loss_grad` beside the original
function. The generated function returns the loss and writes its derivatives
into `d_rate` and `d_capacity`. Those derivatives account for the entire
simulation, including the branch that selects which steps contribute to
the error. The compiler itself has no differentiation code.

<section class="code-note" data-code-line="17">

### Improve the fit.

The outer loop uses the gradient to improve the parameter estimates over
200 iterations. Checkpointing saves the simulation state every 64 steps
and replays each block when calculating derivatives, reducing the amount
of intermediate state it needs to retain. Starting from 0.5 and 30, the
fit reaches approximately 0.9006 and 49.9922.

The full program also compares the generated gradient with finite
differences before fitting.

[Full example](https://github.com/gwf/x2c/blob/main/examples/magic/autodiff-fit.x)
/ <a href="https://github.com/gwf/x2c/blob/main/lib/autodiff.xmacro" data-example-action="source">Autodiff macros</a>

</section>
