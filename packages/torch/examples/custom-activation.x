/*  custom-activation.x -- Train through an x2c-defined swish derivative. */

import "torch" with Torch, Tensor, Module, Optimizer, AutogradContext;
#include <stdlib.h>

static Tensor _swish(AutogradContext context, List inputs) {
  Tensor input = inputs[0].tensor();
  context.save_for_backward(%($input));
  return input * input.sigmoid();
}

static List _swish_gradient(AutogradContext context, Tensor gradient) {
  Tensor input = context.saved_tensors()[0].tensor();
  Tensor sigmoid = input.sigmoid();
  Tensor result = gradient * (sigmoid + input * sigmoid * (1 - sigmoid));
  return %($result);
}

int main(void) {
  Scope.retain();
  defer Scope.release();
  Torch.manual_seed(7);
  String device = getenv("TORCH_DEVICE");
  if (!device) device = "cpu";
  Module model = Module.composed();
  model.register("hidden", Module.linear(1, 16));
  model.register("output", Module.linear(16, 1));
  model.to_device(device);
  Optimizer optimizer = Optimizer.adam(model, 0.02);
  Tensor input = Tensor.arange(-2.0, 2.0, 0.0625, XT_FLOAT32)
    .reshape(%(64 1)).to_device(device, XT_FLOAT32, 0, 0);
  Tensor target = input.square();
  Func forward = _swish, backward = _swish_gradient;
  double first = 0, last = 0;
  for (int i = 0; i < 300; i++) {
    Scope.retain();
    defer Scope.release();
    optimizer.zero_grad();
    Tensor hidden = model.child("hidden").forward(input);
    Tensor active = Tensor.custom(forward, backward, %($hidden));
    Tensor loss = Tensor.mse_loss(model.child("output").forward(active), target);
    loss.backward_callbacks();
    optimizer.step();
    last = loss.item().double();
    if (i == 0) first = last;
  }
  printf("custom swish on %s: loss %.6f -> %.6f\n", device, first, last);
  return last < 0.01 ? 0 : 1;
}
