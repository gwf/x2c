/*  test-modules.x -- Native layers, sequential composition, the x2c
    learning-rate schedules, TorchScript loading, and the MNIST reader. */

import "torch" with Torch, Tensor, Module, Optimizer, Scheduler, JitModule;

#include "test-support.x"
#include <math.h>
#include <sys/stat.h>

$(import "../../../unittest/test-macros.xmacro")

#define EXPECT_NEAR(actual, expected, tolerance) \
  EXPECT_TRUE(fabs((actual) - (expected)) < (tolerance))

/* The names a module's parameters and buffers enumerate under, joined,
   so a test can compare them with Python's state_dict() keys. */
static String _names(List pairs) {
  List names = %();
  foreach (List pair, pairs) {
    String name = pair[0].str();
    names = names.append(%($name));
  }
  return names.str();
}

static String _shape(Tensor t) => t.shape().str();

static void modules_shapes(void) {
  $test.scoped();
  Torch.manual_seed(7);
  Module convolution = Module.conv2d(1, 8, 3);
  Tensor image = Tensor.randn(%(2 1 28 28), XT_FLOAT32);
  EXPECT_STR_EQ(_shape(convolution.forward(image)), "( 2 8 26 26 )");
  Module padded = Module.conv2d_with(1, 4, 3, 1, 1, 1, 1, 1);
  EXPECT_STR_EQ(_shape(padded.forward(image)), "( 2 4 28 28 )");

  Module line = Module.conv1d(2, 4, 3);
  Tensor series = Tensor.randn(%(2 2 10), XT_FLOAT32);
  EXPECT_STR_EQ(_shape(line.forward(series)), "( 2 4 8 )");

  Module normalize = Module.batch_norm2d(1);
  EXPECT_STR_EQ(_shape(normalize.forward(image)), "( 2 1 28 28 )");
  Module rows = Module.batch_norm1d(4);
  Tensor table = Tensor.randn(%(6 4), XT_FLOAT32);
  EXPECT_STR_EQ(_shape(rows.forward(table)), "( 6 4 )");
  Module layer = Module.layer_norm(%(4));
  EXPECT_STR_EQ(_shape(layer.forward(table)), "( 6 4 )");
  EXPECT_NEAR(layer.forward(table).mean().item().double(), 0.0, 1e-5);

  Module lookup = Module.embedding(5, 3);
  Tensor indexes = Tensor.of(%((0 4) (2 1)), %(2 2), XT_INT64);
  EXPECT_STR_EQ(_shape(lookup.forward(indexes)), "( 2 2 3 )");

  Module pool = Module.max_pool2d(2);
  EXPECT_STR_EQ(_shape(pool.forward(image)), "( 2 1 14 14 )");
  Module average = Module.avg_pool2d(2);
  EXPECT_STR_EQ(_shape(average.forward(image)), "( 2 1 14 14 )");
  EXPECT_STR_EQ(_shape(Module.flatten().forward(image)), "( 2 784 )");

  Tensor signed_values = Tensor.of(%(-1.0 0.5), %(2), XT_FLOAT32);
  EXPECT_NEAR(Module.relu().forward(signed_values).sum().item().double(),
              0.5, 1e-6);
  EXPECT_NEAR(Module.tanh().forward(signed_values).sum().item().double(),
              tanh(-1.0) + tanh(0.5), 1e-6);
  EXPECT_NEAR(Module.sigmoid().forward(signed_values).sum().item().double(),
              1.0 / (1.0 + exp(1.0)) + 1.0 / (1.0 + exp(-0.5)), 1e-6);
}

/* Parameter and buffer names are libtorch's, which are Python's;
   verify-python compares these same strings with the pinned wheel. */
static void modules_names(void) {
  $test.scoped();
  EXPECT_STR_EQ(_names(Module.conv2d(1, 8, 3).named_parameters()),
                "( weight bias )");
  Module normalize = Module.batch_norm2d(3);
  EXPECT_STR_EQ(_names(normalize.named_parameters()), "( weight bias )");
  EXPECT_STR_EQ(_names(normalize.named_buffers()),
                "( running_mean running_var num_batches_tracked )");
  EXPECT_STR_EQ(_names(Module.lstm(3, 4, 1, 1).named_parameters()),
                "( weight_ih_l0 weight_hh_l0 bias_ih_l0 bias_hh_l0 )");
  EXPECT_STR_EQ(_names(Module.embedding(5, 3).named_parameters()),
                "( weight )");

  /* A child's names are qualified by the name it was registered under. */
  Module model = Module.composed();
  model.register("features", Module.conv2d(1, 2, 3));
  model.register("norm", Module.batch_norm2d(2));
  EXPECT_STR_EQ(_names(model.named_parameters()),
                "( features.weight features.bias norm.weight norm.bias )");
  EXPECT_STR_EQ(_names(model.named_buffers()),
                "( norm.running_mean norm.running_var "
                "norm.num_batches_tracked )");
}

/* A sequential root forwards its children in order under PyTorch's own
   names, so it equals the same calls written out. */
static void modules_sequential(void) {
  $test.scoped();
  Torch.manual_seed(11);
  Module model = Module.sequential();
  Module first = model.push(Module.linear(3, 4));
  model.push(Module.relu());
  Module last = model.push(Module.linear(4, 2));
  EXPECT_STR_EQ(_names(model.named_parameters()),
                "( 0.weight 0.bias 2.weight 2.bias )");

  Tensor x = Tensor.randn(%(5 3), XT_FLOAT32);
  Tensor chained = last.forward(first.forward(x).relu());
  EXPECT_TRUE(model.forward(x).allclose(chained, 1e-6, 1e-8));

  /* A child with no native forward is a clear failure, not a silent
     skip. */
  Module mixed = Module.sequential();
  mixed.push(Module.composed());
  int caught = 0;
  try { mixed.forward(x); }
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 1);
}

/* Dropout and batch normalization read the training mode, so the mode
   the module tree carries has to reach them. */
static void modules_training_mode(void) {
  $test.scoped();
  Tensor x = Tensor.ones(%(4 3), XT_FLOAT32);
  Module drop = Module.dropout(1.0);
  EXPECT_NEAR(drop.forward(x).sum().item().double(), 0.0, 1e-6);
  drop.eval();
  EXPECT_TRUE(drop.forward(x).equal(x));

  Module normalize = Module.batch_norm1d(3);
  EXPECT_NEAR(normalize.buffers()[0].tensor().sum().item().double(), 0.0,
              1e-9);
  Tensor batch = Tensor.of(%((1 2 3) (3 4 5)), %(2 3), XT_FLOAT32);
  normalize.forward(batch);
  /* running_mean is 0.9 * 0 + 0.1 * the batch mean, PyTorch's momentum. */
  Array running = normalize.buffers()[0].tensor().to_values();
  EXPECT_NEAR(running[0].double(), 0.2, 1e-6);
  EXPECT_NEAR(running[2].double(), 0.4, 1e-6);
  EXPECT_INT_EQ(normalize.buffers()[2].tensor().item().integer(), 1);

  /* In eval the running statistics are used and no longer updated. */
  normalize.eval();
  normalize.forward(batch);
  EXPECT_NEAR(normalize.buffers()[0].tensor().to_values()[0].double(), 0.2,
              1e-6);
}

/* Buffers travel with the parameters through the pickle path. */
static void modules_state_round_trip(void) {
  $test.scoped();
  Torch.manual_seed(13);
  Module model = Module.composed();
  model.register("norm", Module.batch_norm1d(3));
  Tensor batch = Tensor.of(%((1 2 3) (3 4 5)), %(2 3), XT_FLOAT32);
  model.child("norm").forward(batch);
  model.save("builds/test-modules-state.pt");

  Module fresh = Module.composed();
  fresh.register("norm", Module.batch_norm1d(3));
  EXPECT_NEAR(fresh.buffers()[0].tensor().sum().item().double(), 0.0, 1e-9);
  fresh.load("builds/test-modules-state.pt");
  EXPECT_TRUE(fresh.buffers()[0].tensor()
              .allclose(model.buffers()[0].tensor(), 1e-6, 1e-8));
  EXPECT_STR_EQ(_names(fresh.named_buffers()),
                "( norm.running_mean norm.running_var "
                "norm.num_batches_tracked )");

  /* to_dtype converts parameters and buffers together. */
  EXPECT_INT_EQ(model.parameters()[0].tensor().dtype(), XT_FLOAT32);
  model.to_dtype(XT_FLOAT64);
  EXPECT_INT_EQ(model.parameters()[0].tensor().dtype(), XT_FLOAT64);
  EXPECT_INT_EQ(model.buffers()[0].tensor().dtype(), XT_FLOAT64);
}

static void modules_recurrent(void) {
  $test.scoped();
  Torch.manual_seed(17);
  Module memory = Module.lstm(3, 4, 1, 1);
  Tensor series = Tensor.randn(%(2 5 3), XT_FLOAT32);
  List result = memory.forward_state(series);
  EXPECT_INT_EQ(result.len(), 3);
  EXPECT_STR_EQ(_shape(result[0].tensor()), "( 2 5 4 )");
  EXPECT_STR_EQ(_shape(result[1].tensor()), "( 1 2 4 )");
  EXPECT_STR_EQ(_shape(result[2].tensor()), "( 1 2 4 )");
  /* The last step of the output is the final hidden state. */
  EXPECT_TRUE(result[0].tensor().select(1, 4)
              .allclose(result[1].tensor().select(0, 0), 1e-6, 1e-8));

  Module gated = Module.gru(3, 4, 2, 1);
  List pair = gated.forward_state(series);
  EXPECT_INT_EQ(pair.len(), 2);
  EXPECT_STR_EQ(_shape(pair[0].tensor()), "( 2 5 4 )");
  EXPECT_STR_EQ(_shape(pair[1].tensor()), "( 2 2 4 )");

  int caught = 0;
  try { Module.linear(3, 4).forward_state(series); }
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 1);
}

static void modules_losses(void) {
  $test.scoped();
  /* A logit certain of the right class costs almost nothing. */
  Tensor confident = Tensor.of(%((20 -20 -20) (-20 20 -20)), %(2 3),
                               XT_FLOAT32);
  Tensor classes = Tensor.of(%(0 1), %(2), XT_INT64);
  EXPECT_NEAR(Tensor.cross_entropy(confident, classes).item().double(), 0.0,
              1e-6);
  Tensor wrong = Tensor.of(%(1 0), %(2), XT_INT64);
  EXPECT_TRUE(Tensor.cross_entropy(confident, wrong).item().double() > 10.0);
  EXPECT_NEAR(Tensor.nll_loss(confident.log_softmax(1), classes)
              .item().double(), 0.0, 1e-6);

  Tensor logits = Tensor.of(%(20 -20), %(2), XT_FLOAT32);
  Tensor targets = Tensor.of(%(1 0), %(2), XT_FLOAT32);
  EXPECT_NEAR(Tensor.bce_with_logits(logits, targets).item().double(), 0.0,
              1e-6);

  /* l1_loss and huber_loss come from the generated tier with the
     schema's own reduction argument: 1 is mean. */
  Tensor a = Tensor.of(%(1 3), %(2), XT_FLOAT32);
  Tensor b = Tensor.of(%(2 1), %(2), XT_FLOAT32);
  EXPECT_NEAR(a.l1_loss(b, 1).item().double(), 1.5, 1e-6);
  EXPECT_NEAR(a.huber_loss(b, 1, 1.0).item().double(), 1.0, 1e-6);
}

/* Each x2c schedule is the arithmetic its documentation states, checked
   against a rate computed here. */
static void modules_schedules(void) {
  $test.scoped();
  Module layer = Module.linear(2, 1);
  Optimizer sgd = Optimizer.sgd(layer, 1.0);
  Scheduler cosine = Scheduler.cosine(sgd, 4, 0.0);
  EXPECT_NEAR(sgd.lr(), 1.0, 1e-12);
  double expected[4] = { 0.853553390593, 0.5, 0.146446609407, 0.0 };
  for (int step = 0; step < 4; step++) {
    cosine.step();
    EXPECT_NEAR(sgd.lr(), expected[step], 1e-9);
  }
  /* Past t_max the rate stays at the floor. */
  cosine.step();
  EXPECT_NEAR(sgd.lr(), 0.0, 1e-12);
  EXPECT_INT_EQ(cosine.steps(), 5);

  Optimizer warm = Optimizer.sgd(layer, 0.0);
  Scheduler ramp = Scheduler.linear_warmup(warm, 4, 1.0);
  EXPECT_NEAR(warm.lr(), 0.25, 1e-12);
  ramp.step();
  EXPECT_NEAR(warm.lr(), 0.5, 1e-12);
  ramp.step();
  EXPECT_NEAR(warm.lr(), 0.75, 1e-12);
  ramp.step();
  EXPECT_NEAR(warm.lr(), 1.0, 1e-12);
  ramp.step();
  EXPECT_NEAR(warm.lr(), 1.0, 1e-12);

  Optimizer stepped = Optimizer.sgd(layer, 1.0);
  Scheduler milestones = Scheduler.multistep(stepped, %(2 4), 0.5);
  EXPECT_NEAR(stepped.lr(), 1.0, 1e-12);
  milestones.step();
  EXPECT_NEAR(stepped.lr(), 1.0, 1e-12);
  milestones.step();
  EXPECT_NEAR(stepped.lr(), 0.5, 1e-12);
  milestones.step();
  EXPECT_NEAR(stepped.lr(), 0.5, 1e-12);
  milestones.step();
  EXPECT_NEAR(stepped.lr(), 0.25, 1e-12);

  /* An x2c schedule advances without a metric, and says so. */
  int caught = 0;
  try { milestones.step_metric(1.0); }
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 1);
}

/* TorchScript: the failure path runs everywhere, and verify-jit runs a
   real scripted model exported by the pinned Python torch. */
static void modules_torchscript(void) {
  $test.scoped();
  File out = File.open("builds/not-a-model.pt", "wb");
  out.puts("this is not a TorchScript archive\n");
  out.close();
  int caught = 0;
  try { JitModule.load("builds/not-a-model.pt"); }
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 1);
  try { JitModule.load("builds/no-such-model.pt"); }
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 2);
}

/* A synthetic IDX set, so the reader is exercised wherever the real
   files are absent. The format is the one MNIST publishes: a big-endian
   magic, a count, and for the images a 28 by 28 shape. libtorch's reader
   checks the published counts, so the synthetic set is the 10,000-row
   test split; a synthetic training split would be six times the size for
   no more coverage. */
static void _put_be32(File out, long value) {
  unsigned char header[4];
  header[0] = (value >> 24) & 0xff;
  header[1] = (value >> 16) & 0xff;
  header[2] = (value >> 8) & 0xff;
  header[3] = value & 0xff;
  out.write_all(header, 4);
}

static void _write_images(String path, long count) {
  File out = File.open(path, "wb");
  defer out.close();
  _put_be32(out, 2051);
  _put_be32(out, count);
  _put_be32(out, 28);
  _put_be32(out, 28);
  unsigned char *pixels = Scope.calloc(784, 1);
  for (long image = 0; image < count; image++) {
    for (int pixel = 0; pixel < 784; pixel++)
      pixels[pixel] = (unsigned char) ((image * 31 + pixel * 7) % 256);
    out.write_all(pixels, 784);
  }
}

static void _write_labels(String path, long count) {
  File out = File.open(path, "wb");
  defer out.close();
  _put_be32(out, 2049);
  _put_be32(out, count);
  unsigned char *classes = Scope.calloc(count, 1);
  for (long index = 0; index < count; index++)
    classes[index] = (unsigned char) (index % 10);
  out.write_all(classes, count);
}

static void modules_mnist_reader(void) {
  $test.scoped();
  String root = "builds/mnist-synthetic";
  mkdir(root, 0755);
  _write_images(%"$root/t10k-images-idx3-ubyte", 10000);
  _write_labels(%"$root/t10k-labels-idx1-ubyte", 10000);

  List set = Torch.mnist(root, 0);
  Tensor images = set[0].tensor(), targets = set[1].tensor();
  EXPECT_STR_EQ(_shape(images), "( 10000 1 28 28 )");
  EXPECT_STR_EQ(_shape(targets), "( 10000 )");
  EXPECT_INT_EQ(images.dtype(), XT_FLOAT32);
  EXPECT_INT_EQ(targets.dtype(), XT_INT64);
  /* The reader scales the bytes into [0, 1]. */
  EXPECT_TRUE(images.max().item().double() <= 1.0);
  EXPECT_TRUE(images.min().item().double() >= 0.0);
  EXPECT_INT_EQ(targets[0].item().integer(), 0);
  EXPECT_INT_EQ(targets[9].item().integer(), 9);

  /* Batching is x2c: a permutation and an index_select over the two
     tensors the reader returns. */
  Tensor pick = Torch.randperm(10000).narrow(0, 0, 32);
  EXPECT_STR_EQ(_shape(images.index_select(0, pick)), "( 32 1 28 28 )");

  int caught = 0;
  try { Torch.mnist("builds/no-such-mnist", 0); }
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 1);
  /* The published row count is part of the format the reader checks. */
  String short_root = "builds/mnist-short";
  mkdir(short_root, 0755);
  _write_images(%"$short_root/t10k-images-idx3-ubyte", 8);
  _write_labels(%"$short_root/t10k-labels-idx1-ubyte", 8);
  try { Torch.mnist(short_root, 0); }
  catch %(bad-state (library "torch") *): caught++;
  EXPECT_INT_EQ(caught, 2);
}

/* One training step over a real convolutional model, so the layers,
   the loss, and the optimizer are exercised together. */
static void modules_train_a_small_cnn(void) {
  $test.scoped();
  Torch.manual_seed(19);
  Module model = Module.sequential();
  model.push(Module.conv2d(1, 4, 3));
  model.push(Module.relu());
  model.push(Module.max_pool2d(2));
  model.push(Module.flatten());
  model.push(Module.linear(4 * 13 * 13, 10));

  Tensor images = Tensor.randn(%(8 1 28 28), XT_FLOAT32);
  Tensor classes = Tensor.of(%(0 1 2 3 4 5 6 7), %(8), XT_INT64);
  Optimizer adam = Optimizer.adam(model, 0.01);
  double first = 0.0, last = 0.0;
  for (int step = 0; step < 20; step++) {
    Scope.retain();
    {
      defer Scope.release();
      adam.zero_grad();
      Tensor loss = Tensor.cross_entropy(model.forward(images), classes);
      loss.backward();
      adam.step();
      last = loss.item().double();
      if (!step) first = last;
    }
  }
  EXPECT_TRUE(last < first * 0.5);
}

void modules_suite(void) {
  $test.run(modules_shapes);
  $test.run(modules_names);
  $test.run(modules_sequential);
  $test.run(modules_training_mode);
  $test.run(modules_state_round_trip);
  $test.run(modules_recurrent);
  $test.run(modules_losses);
  $test.run(modules_schedules);
  $test.run(modules_torchscript);
  $test.run(modules_mnist_reader);
  $test.run(modules_train_a_small_cnn);
}

int main(void) {
  TestHarness_begin();
  $test.suite(modules_suite);
  return TestHarness_finish();
}
