/*  mps-kernels.x -- Record a generated operator's native MPS limitation. */

import "torch" with Torch, Tensor;

int main(void) {
  if (!Torch.mps_available()) {
    printf("MPS kernel probe skipped: device unavailable\n");
    return 0;
  }
  Scope.retain();
  defer Scope.release();
  Tensor matrix = Torch.eye(2, XT_FLOAT32, "mps");
  int caught = 0;
  try matrix.linalg_eig();
  catch %(bad-state (library "torch") *): {
    printf("MPS linalg_eig: %s\n", xt_last_error());
    caught = 1;
  }
  return caught ? 0 : 1;
}
