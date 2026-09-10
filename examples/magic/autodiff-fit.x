// Fit the two parameters of a logistic growth model to observations by
// gradient descent. The loss integrates the model with 4000 Euler steps and
// compares it with the observed curve along the way, so its gradient runs
// through a long loop with a branch inside; $ad.checkpoint keeps the tape
// small by replaying the loop in blocks of 64 steps.
#include "x2c.x"
#include "typed-array.x"
#include <stdio.h>
#include <math.h>
$(import "autodiff.xmacro")

// The observations come from the same model with rate 0.9 and capacity 50.
static double observed(double t) => 50.0 / (1.0 + 49.0 * exp(-0.9 * t));

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
  printf("loss %.6f\n", value);
  printf("d/drate     %.6f  finite difference %.6f\n", d_rate,
         (loss(rate + h, capacity) - loss(rate - h, capacity)) / (2 * h));
  printf("d/dcapacity %.6f  finite difference %.6f\n", d_capacity,
         (loss(rate, capacity + h) - loss(rate, capacity - h)) / (2 * h));
  for (int i = 1; i <= 200; i++) {
    value = loss_grad(rate, capacity, &d_rate, &d_capacity);
    rate -= 1e-5 * d_rate;
    capacity -= 1e-2 * d_capacity;
    if (i % 50 == 0)
      printf("step %2d  loss %10.6f  rate %.4f  capacity %.4f\n",
             i, value, rate, capacity);
  }
  printf("observed(4) %.4f  model(4) %.4f\n", observed(4.0),
         capacity / (1.0 + (capacity - 1.0) * exp(-rate * 4.0)));
  return 0;
}
