---
slug: torch
section: packages
title: Teach it what a digit looks like.
image: examples/torch-predictions.svg
imageAlt: Handwritten MNIST test digits with the x2c model's predictions and their actual labels.
imageWidth: 880
imageHeight: 420
---

<!-- ignore: model and training excerpts; dataset loading is in the full example. -->
```x2c,ignore
import "torch" with Torch, Tensor, Module, Optimizer, Scheduler;

static Module _model(void) {
  Module model = Module.sequential();
  model.push(Module.conv2d(1, 8, 3));
  model.push(Module.relu());
  model.push(Module.max_pool2d(2));
  model.push(Module.flatten());
  model.push(Module.linear(8 * 13 * 13, 10));
  return model;
}

Torch.manual_seed(0);
Module model = _model();
Optimizer adam = Optimizer.adam(model, 0.001);
Scheduler anneal = Scheduler.cosine(adam, batches, 0.0001);

Tensor order = Torch.randperm(rows);
for (long batch = 0; batch < batches; batch++) {
  Scope.retain();
  defer Scope.release();
  Tensor pick = order.narrow(0, batch * BATCH, BATCH);
  adam.zero_grad();
  Tensor loss = Tensor.cross_entropy(
    model.forward(images.index_select(0, pick)),
    targets.index_select(0, pick));
  loss.backward();
  adam.step();
  anneal.step();
}
```

The network starts with random weights. Eight convolution filters learn
features from the pixels; pooling reduces their size, and a linear layer
turns them into ten scores, one for each possible digit.

<section class="code-note" data-code-line="19">

### Train on labeled images.

Each batch compares those scores with the correct labels. `backward()`
computes gradients through the network, and Adam uses them to update its
weights. The surrounding loop chooses the images and advances the learning
rate schedule in ordinary x2c.

This run scored 93.23% on the 10,000 test images after one training pass.
The image shows the first twelve test cases, including a 5 it mistakes for
a 6. Predictions were recorded from the x2c program; none of these images
were used to update its weights. Results can vary across machines.

[Full example](https://github.com/gwf/x2c/blob/main/packages/torch/examples/mnist.x)

</section>
