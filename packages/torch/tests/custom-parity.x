/*  custom-parity.x -- Values and gradients for the Python custom-node check. */

import "torch" with Torch, Tensor, AutogradContext, Checkpoint;

static Tensor _swish(AutogradContext context, List inputs) {
  Tensor input = inputs[0].tensor();
  context.save_for_backward(%($input));
  return input * input.sigmoid();
}

static List _gradient(AutogradContext context, Tensor gradient) {
  Tensor input = context.saved_tensors()[0].tensor();
  Tensor sigmoid = input.sigmoid();
  Tensor result = gradient * (sigmoid + input * sigmoid * (1 - sigmoid));
  return %($result);
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  Scope.retain();
  defer Scope.release();
  Tensor input = Tensor.arange(-4.0, 4.0, 0.125, XT_FLOAT32)
    .to_device(argv[1], XT_FLOAT32, 0, 0).requires_grad_(1);
  Tensor output = Tensor.custom(_swish, _gradient, %($input));
  output.square().sum().backward_callbacks();
  Tensor gradient = input.grad();
  Map values = %{};
  values["input"] = input;
  values["output"] = output;
  values["gradient"] = gradient;
  Checkpoint.save(values, argv[2]);
  return 0;
}
