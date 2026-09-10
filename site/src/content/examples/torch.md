---
slug: torch
navTitle: Recognize digits
order: 1
slide: torch
title: Recognize handwritten digits.
description: Train a convolutional network in x2c with the Torch package, then test it on handwriting it has never seen.
source: packages/torch/examples/mnist.x
codeLabel: Model and training loop from mnist.x
extraPanels:
  - torch-evaluation
runIntro: This example uses the Torch package and the MNIST dataset. The pinned package supports Apple Silicon Macs on the CPU and links dynamically to libtorch.
run: |
  ./configure --packages torch
  make -C packages/torch builds/mnist
  mkdir -p data/mnist
  for name in train-images-idx3-ubyte train-labels-idx1-ubyte \
              t10k-images-idx3-ubyte t10k-labels-idx1-ubyte; do
    curl -fL "https://ossci-datasets.s3.amazonaws.com/mnist/$name.gz" | gunzip > "data/mnist/$name"
  done
  ./packages/torch/builds/mnist data/mnist
guide: docs/guide/packages.html
---

## A complete training program.

The full example loads the training and test sets with `Torch.mnist`, creates
its model, trains it, and reports test accuracy. The code above is excerpted
from that program; the source link includes dataset loading and progress
reporting as well.

MNIST contains 60,000 training images and 10,000 test images, each 28 by 28
pixels. This program makes one pass through 937 complete batches of 64,
leaving the final 32 training images out. Training shuffles the image order
and reduces the learning rate from 0.001 toward 0.0001 with a cosine schedule.

## The package behind the program.

The <a href="https://github.com/gwf/x2c/blob/main/packages/torch/README.md" data-example-action="guide">Torch package</a>
provides tensors, automatic differentiation, layers, optimizers,
checkpoints, and TorchScript inference over PyTorch's C++ library.
Tensor operations run in libtorch. The model definition, batching, training
loop, and evaluation here are x2c.

The current package pins libtorch 2.10.0 and supports macOS arm64 on the CPU;
it does not yet provide CUDA, MPS, or a Linux build. Its shared libraries are
required at runtime. The preparation step downloads the pinned library;
the recipe below separately downloads the four MNIST files.

Try adding another convolution, increasing the number of channels, or
training for more than one pass. Compare the result on the test set rather
than the images the model learned from.
