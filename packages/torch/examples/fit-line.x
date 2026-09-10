/*  fit-line.x -- Fit y = 3x - 1 by gradient descent through autograd. */

import "torch" with Torch, Tensor;

int main(void) {
  Scope.retain();
  defer Scope.release();
  Torch.manual_seed(7);

  Tensor x = Tensor.arange(0.0, 8.0, 1.0, XT_FLOAT64).reshape(%(8 1));
  Tensor y = 3.0 * x - 1.0;
  Tensor w = Tensor.randn(%(1 1), XT_FLOAT64).requires_grad_(1);
  Tensor b = Tensor.zeros(%(1), XT_FLOAT64).requires_grad_(1);

  double loss = 0.0;
  for (int step = 0; step < 200; step++) {
    Scope.retain();
    {
      /* Releasing this scope frees the step's tensors and restores the
         grad mode that Torch.no_grad turned off, even if a raise crosses
         the release. */
      defer Scope.release();
      Tensor error = Tensor.mse_loss(x @ w + b, y);
      error.backward();
      loss = error.item().double();
      Torch.no_grad();
      w.add_(w.grad(), -0.02);
      b.add_(b.grad(), -0.02);
      w.zero_grad();
      b.zero_grad();
    }
    if (step % 50 == 0) printf("step %3d  loss %.6f\n", step, loss);
  }
  printf("w %.3f  b %.3f  loss %.2e\n", w.item().double(),
         b.item().double(), loss);
  return 0;
}
