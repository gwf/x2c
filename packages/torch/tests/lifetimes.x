/*  lifetimes.x -- Optional handle-counter proof for custom graphs and Lisp. */

import "torch" with Torch, Tensor, TorchLisp, AutogradContext;
#include "handles.h"
#include <stdio.h>

static Tensor _square(AutogradContext context, List inputs) {
  Tensor input = inputs[0].tensor();
  context.save_for_backward(%($input));
  return input.square();
}
static List _gradient(AutogradContext context, Tensor gradient) {
  Tensor input = context.saved_tensors()[0].tensor();
  Tensor result = gradient * input * 2;
  return %($result);
}

static long _live(void) {
  long total = 0;
  for (int kind = 0; kind < XT_HANDLE_KINDS; kind++)
    total += xb_handles_live(kind);
  return total;
}

int main(void) {
  if (!xb_handles_enabled()) return 2;
  Scope.retain();
  defer Scope.release();
  long baseline = _live();
  Func forward = _square, backward = _gradient;
  for (int i = 0; i < 64; i++) {
    Scope.retain();
    {
      defer Scope.release();
      Tensor input = Tensor.ones(%(16), XT_FLOAT32).requires_grad_(1);
      Tensor output = Tensor.custom(forward, backward, %($input));
      output.sum().backward_callbacks();
    }
    if (_live() != baseline) return 3;
  }
  Lisp lisp = Lisp.new();
  TorchLisp.install(lisp);
  lisp.eval_string(
    "(def x (torch-tensor '((1 2)) '(1 2) torch-float32)) "
    "(def y (torch-tensor '((3)) '(1 1) torch-float32)) "
    "(def model (torch-linear 2 1)) "
    "(def optimizer (torch-adam model 0.02)) "
    "(defun step () (begin (torch-zero-grad optimizer) "
    "  (let* ((p (torch-forward model x)) (loss (torch-mse p y))) "
    "    (begin (torch-backward loss) (torch-step optimizer) "
    "      (torch-free p) (torch-free loss)))))");
  long retained = _live();
  ScopeStats before = Scope.stats();
  for (int i = 0; i < 128; i++) {
    lisp.eval_string("(step)");
    if (_live() != retained) return 4;
  }
  ScopeStats after = Scope.stats();
  printf("Lisp 128 steps: native handles %ld -> %ld; "
         "live scope allocations %ld -> %ld\n", retained, _live(),
         before.live_allocations, after.live_allocations);
  lisp.destroy();
  if (_live() != baseline) return 5;
  printf("64 custom graphs and Lisp session: all native handles released\n");
  return 0;
}
