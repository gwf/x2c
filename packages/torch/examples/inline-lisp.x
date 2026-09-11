/*  inline-lisp.x -- Train a persistent model through ordinary Lisp calls. */

import "torch" with Torch, TorchLisp;

int main(void) {
  Scope.retain();
  defer Scope.release();
  Torch.manual_seed(7);
  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  TorchLisp.install(lisp);
  lisp.eval_string(
    "(def x (torch-tensor '((-1) (0) (1) (2)) '(4 1) torch-float32)) "
    "(def y (torch-tensor '((-4) (-1) (2) (5)) '(4 1) torch-float32)) "
    "(def model (torch-linear 1 1)) "
    "(def optimizer (torch-sgd model 0.05)) "
    "(defun step () (begin "
    "  (torch-zero-grad optimizer) "
    "  (let* ((prediction (torch-forward model x)) "
    "         (loss (torch-mse prediction y)) "
    "         (value (torch-item loss))) "
    "    (begin (torch-backward loss) "
    "    (torch-step optimizer) "
    "    (torch-free loss) "
    "    (torch-free prediction) value))))");
  double first = lisp.eval_string("(step)").double(), last = first;
  ScopeStats before = Scope.stats();
  for (int i = 0; i < 199; i++) last = lisp.eval_string("(step)").double();
  ScopeStats after = Scope.stats();
  printf("loss %.6f -> %.9f\n", first, last);
  printf("session wrappers remain until Lisp.destroy; native step tensors "
         "are freed\n");
  printf("scope allocations %ld -> %ld\n", before.live_allocations,
         after.live_allocations);
  lisp.eval_string("(torch-save model \"builds/lisp-fit.pt\")");
  return last < 0.0001 ? 0 : 1;
}
