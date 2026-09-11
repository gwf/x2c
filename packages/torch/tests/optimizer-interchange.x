/*  optimizer-interchange.x -- Train or resume a Python-readable Adam state. */

import "torch" with Torch, Tensor, Module, Optimizer;
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 5 && argc != 6) return 2;
  Scope.retain();
  defer Scope.release();
  Torch.manual_seed(7);
  Module model = Module.linear(2, 1);
  model.to_dtype(XT_FLOAT64);
  Optimizer optimizer = Optimizer.adam_with(model, 0.03, 0.8, 0.95,
                                            1e-7, 0.02, 1);
  String model_path = argv[1], state_path = argv[2], prefix = argv[3];
  if (model_path != "-") model.load(model_path);
  if (state_path != "-") optimizer.load_python(state_path);
  model.save(%"${prefix}-before-model.pt");
  optimizer.save_python(%"${prefix}-before-optim.pt");
  if (argc == 6) {
    int caught = 0;
    try optimizer.load_python(argv[5]);
    catch %(bad-state (library "torch") *): caught++;
    if (caught != 1) return 3;
  }
  Tensor x = Tensor.of(%((1 2) (2 1) (-1 3) (0 2)), %(4 2), XT_FLOAT64);
  Tensor y = Tensor.of(%((2) (4) (-3) (-1)), %(4 1), XT_FLOAT64);
  for (int i = 0; i < atoi(argv[4]); i++) {
    Scope.retain();
    defer Scope.release();
    optimizer.zero_grad();
    Tensor loss = Tensor.mse_loss(model.forward(x), y);
    loss.backward();
    optimizer.step();
  }
  model.save(%"${prefix}-model.pt");
  optimizer.save_python(%"${prefix}-optim.pt");
  printf("optimizer state saved\n");
  return 0;
}
