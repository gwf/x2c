/*  mnist.x -- Train a small convolutional network on MNIST for one
    epoch and report its accuracy on the test set.

    The dataset comes from libtorch's own IDX reader as two tensors, and
    the mini-batches are x2c: a permutation and an `index_select`. The
    model is a sequential root, so its forward is one call.
*/

import "torch" with Torch, Tensor, Module, Optimizer, Scheduler;

#include <stdlib.h>

#define BATCH 64

static Module _model(void) {
  Module model = Module.sequential();
  model.push(Module.conv2d(1, 8, 3));
  model.push(Module.relu());
  model.push(Module.max_pool2d(2));
  model.push(Module.flatten());
  model.push(Module.linear(8 * 13 * 13, 10));
  return model;
}

/* The fraction of `images` the model classifies correctly, in chunks so
   the whole test set never forms one graph. */
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

static void _explain(String root) {
  printf("no MNIST files under %s\n", root);
  printf("Download the four IDX files and gunzip them into that "
         "directory:\n");
  printf("  train-images-idx3-ubyte  train-labels-idx1-ubyte\n");
  printf("  t10k-images-idx3-ubyte   t10k-labels-idx1-ubyte\n");
  printf("They are published at https://yann.lecun.com/exdb/mnist/ and "
         "mirrored at\n");
  printf("https://ossci-datasets.s3.amazonaws.com/mnist/ as "
         "train-images-idx3-ubyte.gz\n");
  printf("and the three matching names. Then pass the directory as an "
         "argument or\n");
  printf("set TORCH_MNIST to it.\n");
}

int main(int argc, char **argv) {
  Scope.retain();
  defer Scope.release();
  String root = argc > 1 ? argv[1] : getenv("TORCH_MNIST");
  if (!root) root = "data/mnist";

  List training, test;
  try {
    training = Torch.mnist(root, 1);
    test = Torch.mnist(root, 0);
  }
  catch %(bad-state (library "torch") *): {
    _explain(root);
    return 0;
  }

  Tensor images = training[0].tensor(), targets = training[1].tensor();
  Tensor test_images = test[0].tensor(), test_targets = test[1].tensor();
  long rows = images.size(0), batches = rows / BATCH;
  printf("mnist %s  train %ld  test %ld\n", root, rows,
         test_images.size(0));

  Torch.manual_seed(0);
  Module model = _model();
  String device = getenv("TORCH_DEVICE");
  if (!device) device = "cpu";
  model.to_device(device);
  images = images.to_device(device, XT_FLOAT32, 0, 0);
  targets = targets.to_device(device, XT_INT64, 0, 0);
  test_images = test_images.to_device(device, XT_FLOAT32, 0, 0);
  test_targets = test_targets.to_device(device, XT_INT64, 0, 0);
  printf("device %s\n", images.device());
  Optimizer adam = Optimizer.adam(model, 0.001);
  /* libtorch ships StepLR and ReduceLROnPlateau; this cosine anneal is
     one of the x2c schedules over Optimizer.set_lr. */
  String requested_epochs = getenv("TORCH_EPOCHS");
  int epochs = requested_epochs ? atoi(requested_epochs) : 1;
  if (epochs < 1) return 1;
  Scheduler anneal = Scheduler.cosine(adam, batches * epochs, 0.0001);

  for (int epoch = 0; epoch < epochs; epoch++) {
    printf("epoch %d of %d\n", epoch + 1, epochs);
    Tensor order = Torch.randperm(rows).to_device(device, XT_INT64, 0, 0);
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
      if (batch % 100 == 0)
        printf("batch %4ld  loss %.6f  lr %.6f\n", batch,
               loss.item().double(), adam.lr());
    }
  }
  double accuracy = _accuracy(model, test_images, test_targets);
  model.save("builds/mnist-model.pt");
  Module reloaded = _model();
  reloaded.load("builds/mnist-model.pt");
  reloaded.to_device(device);
  double restored = _accuracy(reloaded, test_images, test_targets);
  printf("test accuracy %.4f; checkpoint reload %.4f\n", accuracy, restored);
  return accuracy == restored ? 0 : 1;
}
