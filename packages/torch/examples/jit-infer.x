/*  jit-infer.x -- Run a TorchScript model exported from Python.

    x2c loads and runs a scripted module; it cannot produce one. The two
    files here come from `make -C packages/torch verify-jit`, which
    scripts them in the pinned Python torch and then compares the numbers
    this program prints with Python's own.
*/

import "torch" with Torch, Tensor, JitModule;

static void _print_row(String label, Tensor row) {
  printf("%s", label);
  foreach (Var value, row.to_values()) printf(" %.6f", value.double());
  printf("\n");
}

int main(int argc, char **argv) {
  Scope.retain();
  defer Scope.release();
  String path = argc > 1 ? argv[1] : "builds/scripted.pt";

  JitModule model = JitModule.load(path);
  model.eval();

  /* A fixed batch, so the Python side can reproduce it exactly. */
  Tensor x = Tensor.arange(0.0, 8.0, 1.0, XT_FLOAT32).reshape(%(2 4)) / 8.0;

  Torch.inference_mode();
  List results = model.forward(%($x));
  Tensor logits = results[0].tensor();
  printf("model %s\n", path);
  printf("input %s\n", x.shape().str());
  for (long row = 0; row < logits.size(0); row++)
    _print_row(%"logits $row", logits[row]);

  /* A scripted forward returning a tuple of tensors arrives as a longer
     List; this one adds the predicted class per row. */
  JitModule pair = JitModule.load("builds/scripted-pair.pt");
  pair.eval();
  List both = pair.forward(%($x));
  printf("tuple results %d\n", both.len());
  _print_row("classes", both[1].tensor());
  return 0;
}
