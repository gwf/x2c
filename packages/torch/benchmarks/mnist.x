/*  mnist.x -- Application 2: MNIST convolutional classification.

    Native modules on both sides. The model is one `Module.sequential`,
    which is what Python's `nn.Sequential` is, and libtorch names its
    children by position in both languages, so one checkpoint fits both.
    No dropout, so neither side draws an RNG mask.

    The IDX files are read in place through `Torch.mnist`; only the
    initial parameters, the buffers, and the epoch permutations are
    artifacts. BatchNorm's running statistics move in train mode, so they
    are part of the comparison rather than an implementation detail.

      mnist check <artifacts> <out>
      mnist time  <artifacts> <out> epoch <batches>
*/

import "torch" with Torch, Tensor, Module, Optimizer, Checkpoint;

#include <stdlib.h>
#include <string.h>
#include "bench.x"

#define ARTIFACT_VERSION 1
#define CHANNELS1 16
#define CHANNELS2 32
#define KERNEL 3
#define PADDING 1
#define POOL 2
#define FLAT 1568
#define HIDDEN 128
#define CLASSES 10
#define BATCH 64
#define EPOCHS 2
#define BATCHES_PER_EPOCH 938
#define LR 0.001
#define MEAN 0.1307
#define STD 0.3081
#define WARMUP 20

#pragma private

static Map _artifact(String directory, String name) {
  String path = %"$directory/$name";
  Map values = Checkpoint.load(path);
  long version = values["meta.version"].tensor().item().integer();
  if (version != ARTIFACT_VERSION)
    raise %(bad-state (artifact $name) (version $version)
            (reason "artifact version does not match this program"));
  return values;
}

static Module _cnn(void) {
  Module model = Module.sequential();
  model.push(Module.conv2d_with(1, CHANNELS1, KERNEL, 1, PADDING, 1, 1, 1));
  model.push(Module.batch_norm2d(CHANNELS1));
  model.push(Module.relu());
  model.push(Module.max_pool2d(POOL));
  model.push(Module.conv2d_with(CHANNELS1, CHANNELS2, KERNEL, 1, PADDING, 1,
                                1, 1));
  model.push(Module.batch_norm2d(CHANNELS2));
  model.push(Module.relu());
  model.push(Module.max_pool2d(POOL));
  model.push(Module.flatten());
  model.push(Module.linear(FLAT, HIDDEN));
  model.push(Module.relu());
  model.push(Module.linear(HIDDEN, CLASSES));
  return model;
}

static Module _built(String directory, String name) {
  Module model = _cnn();
  model.load(%"$directory/$name");
  return model;
}

/* The two tensors Torch.mnist returns, with the fixed normalization
   applied once. Both languages use these constants. */
static List _dataset(String root, int train) {
  List loaded = Torch.mnist(root, train);
  Tensor images = loaded[0].tensor(), targets = loaded[1].tensor();
  /* The operator rows resolve on the operand's type, and a `#define`
     constant is still an identifier there, so the two constants are
     ordinary doubles. */
  double mean = MEAN, deviation = STD;
  Tensor normalized = (images - mean) / deviation;
  return %($normalized $targets);
}

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
    correct += model.forward(images.narrow(0, start, span)).argmax(1, 0)
      .eq(targets.narrow(0, start, span)).sum().item().integer();
  }
  model.train();
  return (double) correct / (double) total;
}

/* One mini-batch, one scope. The final partial batch of an epoch is kept
   on both sides rather than dropped. */
static void _train(Module model, Optimizer adam, Tensor images,
                   Tensor targets, Tensor order, int count, int offset) {
  long rows = images.size(0);
  int per_epoch = (int) ((rows + BATCH - 1) / BATCH);
  long epochs = order.size(0);
  for (int index = 0; index < count; index++) {
    int position = (offset + index) % per_epoch;
    long epoch = ((offset + index) / per_epoch) % epochs;
    long start = (long) position * BATCH;
    long span = rows - start < BATCH ? rows - start : BATCH;
    Scope.retain();
    defer Scope.release();
    Tensor pick = order.select(0, epoch).narrow(0, start, span);
    adam.zero_grad();
    Tensor loss = Tensor.cross_entropy(
      model.forward(images.index_select(0, pick)),
      targets.index_select(0, pick));
    loss.backward();
    adam.step();
  }
}

static void _record_profile(void) {
  Bench.record_int("cfg_channels1", CHANNELS1);
  Bench.record_int("cfg_channels2", CHANNELS2);
  Bench.record_int("cfg_flat", FLAT);
  Bench.record_int("cfg_hidden", HIDDEN);
  Bench.record_int("cfg_batch", BATCH);
  Bench.record_int("cfg_epochs", EPOCHS);
  Bench.record_int("cfg_batches_per_epoch", BATCHES_PER_EPOCH);
  Bench.record("cfg_lr", LR);
  Bench.record_int("cfg_artifact_version", ARTIFACT_VERSION);
}

static void _save_state(Module model, Map values, String prefix) {
  foreach (List pair, model.named_parameters()) {
    String name = pair[0].str();
    values[%"$prefix.$name"] = pair[1].tensor().clone();
  }
  foreach (List pair, model.named_buffers()) {
    String name = pair[0].str();
    values[%"buffer.$name"] = pair[1].tensor().to_dtype(XT_FLOAT32);
  }
}

/* ---- check ---- */

static int _check(String artifacts, String out, String root) {
  Map order_values = _artifact(artifacts, "mnist-batches.pt");
  Tensor order = order_values["order"].tensor();
  List train = _dataset(root, 1), test = _dataset(root, 0);
  Tensor images = train[0].tensor(), targets = train[1].tensor();
  Tensor test_images = test[0].tensor(), test_targets = test[1].tensor();
  Bench.record("data_checksum",
               images.narrow(0, 0, 1000).sum().item().double());
  Bench.record("test_checksum",
               test_images.narrow(0, 0, 1000).sum().item().double());

  Module model = _built(artifacts, "mnist-init.pt");
  model.train();
  Optimizer adam = Optimizer.adam(model, LR);
  Tensor pick = order.select(0, 0).narrow(0, 0, BATCH);
  Tensor output = model.forward(images.index_select(0, pick));
  Tensor loss = Tensor.cross_entropy(output, targets.index_select(0, pick));
  adam.zero_grad();
  loss.backward();
  Map step1 = %{};
  step1["probe.output"] = output;
  step1["probe.loss"] = loss;
  foreach (List pair, model.named_parameters()) {
    String name = pair[0].str();
    step1[%"grad.$name"] = pair[1].tensor().grad();
  }
  adam.step();
  _save_state(model, step1, "step1");
  Checkpoint.save(step1, %"$out/mnist-x2c-step1.pt");
  Bench.record("probe_loss", loss.item().double());

  Module untrained = _built(artifacts, "mnist-init.pt");
  Bench.record("untrained_accuracy",
               _accuracy(untrained, test_images, test_targets));

  Module trained = _built(artifacts, "mnist-init.pt");
  trained.train();
  Optimizer trainer = Optimizer.adam(trained, LR);
  _train(trained, trainer, images, targets, order,
         BATCHES_PER_EPOCH * EPOCHS, 0);
  Bench.record("trained_accuracy",
               _accuracy(trained, test_images, test_targets));
  {
    Scope.retain();
    defer Scope.release();
    /* Everything the checkpoint holds is created in this scope and saved
       before it closes: a Map outlives a scope, but the Tensor wrappers
       it refers to do not. `no_grad` rather than inference mode, because
       the pickler detaches what it writes. */
    Torch.no_grad();
    Map final = %{};
    _save_state(trained, final, "final");
    trained.eval();
    final["predictions"] =
      trained.forward(test_images.narrow(0, 0, 2000)).clone();
    trained.train();
    Checkpoint.save(final, %"$out/mnist-x2c-final.pt");
  }

  /* Reload must reproduce the predictions, buffers included. */
  String checkpoint = %"$out/mnist-x2c-model.pt";
  trained.save(checkpoint);
  Module reloaded = _cnn();
  reloaded.load(checkpoint);
  Bench.record("reloaded_accuracy",
               _accuracy(reloaded, test_images, test_targets));
  Bench.record_int("mode_after_reload", reloaded.is_training());
  return 0;
}

/* ---- time ---- */

static int _time(String artifacts, String out, String root, String variant,
                 int batches) {
  Bench.record_text("variant", variant);
  Bench.record_int("threads", Torch.num_threads());
  Map order_values = _artifact(artifacts, "mnist-batches.pt");
  Tensor order = order_values["order"].tensor();
  List train = _dataset(root, 1);
  Tensor images = train[0].tensor(), targets = train[1].tensor();
  Bench.sample("loaded", 0);

  Module warm = _built(artifacts, "mnist-init.pt");
  warm.train();
  double warm_start = Bench.now();
  _train(warm, Optimizer.adam(warm, LR), images, targets, order, WARMUP, 0);
  Bench.record("warmup_seconds", Bench.now() - warm_start);

  Module model = _built(artifacts, "mnist-init.pt");
  model.train();
  Optimizer adam = Optimizer.adam(model, LR);
  Bench.sample("ready", 0);
  double start = Bench.now();
  _train(model, adam, images, targets, order, batches, 0);
  double seconds = Bench.now() - start;
  Bench.sample("trained", batches);
  Bench.record_int("batches", batches);
  Bench.record("steady_seconds", seconds);
  Bench.record("batches_per_second", batches / seconds);
  Bench.record("images_per_second", (double) batches * BATCH / seconds);
  Bench.flush();
  return 0;
}

#pragma public

int main(int argc, char **argv) {
  Scope.retain();
  defer Scope.release();
  if (argc < 4) {
    fprintf(stderr, "usage: mnist <check|time> <artifacts> <out>"
                    " [variant] [batches]\n");
    return 2;
  }
  const char *threads = getenv("X2C_TORCH_THREADS");
  Torch.set_num_threads(threads ? atoi(threads) : 1);
  Torch.manual_seed(0);
  Bench.begin(256);
  Bench.record_text("language", "x2c");
  Bench.record_text("torch_version", Torch.version());
  _record_profile();
  Bench.record_int("threads", Torch.num_threads());

  const char *root = getenv("TORCH_MNIST");
  String mnist_root = String.new(root ? root : "/tmp/mnist-real");
  String artifacts = String.new(argv[2]), out = String.new(argv[3]);
  if (!strcmp(argv[1], "check")) return _check(artifacts, out, mnist_root);
  if (!strcmp(argv[1], "time"))
    return _time(artifacts, out, mnist_root, String.new(argv[4]),
                 atoi(argv[5]));
  fprintf(stderr, "mnist: no mode %s\n", argv[1]);
  return 2;
}
