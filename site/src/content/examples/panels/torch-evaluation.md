---
slug: torch-evaluation
section: packages
title: Check it on unseen handwriting.
codeLabel: Evaluation function / excerpt
---

<!-- ignore: evaluation excerpt; package imports are in the full example. -->
```x2c,ignore
static double _accuracy(Module model, Tensor images, Tensor targets) {
  Scope.retain();
  defer Scope.release();
  Torch.no_grad();
  model.eval();
  long total = images.size(0), correct = 0;
  for (long start = 0; start < total; start += 1000) {
    Scope.retain();
    defer Scope.release();
    long span = total - start < 1000 ? total - start : 1000;
    Tensor batch = images.narrow(0, start, span);
    Tensor predicted = model.forward(batch).argmax(1, 0);
    correct += predicted.eq(targets.narrow(0, start, span)).sum()
      .item().integer();
  }
  model.train();
  return (double) correct / (double) total;
}
```

Evaluation runs all 10,000 test images through the trained model. `argmax`
selects the digit with the highest score; `eq` compares it with the label,
and `sum` counts the correct answers. Accuracy is that count divided by the
number of images.

`Torch.no_grad()` disables gradient recording for this scope. There are no
weight updates during evaluation. Processing 1,000 images at a time also
bounds the temporary tensors instead of holding every result at once.

The nested scopes release each batch's tensors when its iteration finishes.
The outer scope restores gradient recording when the function returns.
`eval()` and `train()` select the module's evaluation and training modes;
those matter when experimenting with layers such as dropout.
