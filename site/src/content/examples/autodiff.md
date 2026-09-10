---
slug: autodiff
navTitle: Differentiate a function
order: 4
slide: autodiff
title: Differentiate a function.
description: Generate derivatives with a compile-time Lisp decorator, then use them to fit a growth curve.
source: examples/magic/autodiff-fit.x
output: examples/expected/autodiff-fit.stdout
run: ./x2c run examples/magic/autodiff-fit.x
runIntro: Build x2c, then run the fitting example shown in the output above.
guide: docs/guide/autodiff.html
---

## Fitting a growth curve.

The excerpt above shows the loss function and fitting loop from
`autodiff-fit.x`. The observations are generated from the analytic solution
of the model. The fitted simulation uses Euler integration, so even the
correct parameters produce a small numerical error.

The full program first checks its gradient against central finite differences,
then takes 200 gradient-descent steps toward the model's rate of 0.9 and
capacity of 50.

## Supported operations and limitations.

The transformation supports the documented scalar `double` subset. Reverse
mode supports loops, branches, `break`, `continue`, and early returns; it
requires unique local names. Checkpointed loops cannot contain `return`,
and fixed-block checkpointing still grows with the number of iterations.
The <a href="../../docs/guide/autodiff.html#checkpointing" data-example-action="guide">guide explains the tradeoff</a>,
supported operations, and what the decorators reject.

Try changing the fit's initial rate and capacity to see how they affect
convergence. The finite-difference comparison lets you check the generated
gradient as you experiment.
