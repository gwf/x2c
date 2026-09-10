/*  tabular.x -- Application 1: tabular regression and batched prediction.

    A 128-256-128-8 ReLU network trained with Adam on rows a frozen
    nonlinear teacher produced. Nothing is generated here: the data, the
    exact initial parameters, and every batch's rows come from the
    artifacts prepare.py wrote, so this program and tabular.py start from
    the same numbers rather than from the same seed.

    The forward runs twice over: `native` calls each Linear's own forward,
    and `explicit` writes `x @ weight.t() + bias` over the enumerated
    parameters, as packages/torch/README.md documents. They are the same
    model and different call and lifetime pressure, so they are reported
    apart.

      tabular check   <artifacts> <out>
      tabular time    <artifacts> <out> <native|explicit|predictN> <updates>
      tabular memory  <artifacts> <out> <1|3|5|6> <steps>
*/

import "torch" with Torch, Tensor, Module, Optimizer, Scheduler, Checkpoint;

#include <stdlib.h>
#include <string.h>
#include "bench.x"

#define ARTIFACT_VERSION 1
#define FEATURES 128
#define HIDDEN1 256
#define HIDDEN2 128
#define TARGETS 8
#define BATCH 128
#define UPDATES 1024
#define LR 0.001
#define WARMUP 50
#define PREDICT_REQUESTS 256
#define RETAIN_CAP_BYTES (128 * 1024 * 1024)

#pragma private

/* One artifact, with its version checked before anything reads a tensor.
   A stale dataset compared against a fresh one is a wrong answer, not a
   slow one, so this refuses rather than warns. */
static Map _artifact(String directory, String name) {
  String path = %"$directory/$name";
  Map values = Checkpoint.load(path);
  long version = values["meta.version"].tensor().item().integer();
  if (version != ARTIFACT_VERSION)
    raise %(bad-state (artifact $name) (version $version)
            (reason "artifact version does not match this program"));
  return values;
}

static Module _mlp(void) {
  Module model = Module.composed();
  model.register("l1", Module.linear(FEATURES, HIDDEN1));
  model.register("l2", Module.linear(HIDDEN1, HIDDEN2));
  model.register("l3", Module.linear(HIDDEN2, TARGETS));
  return model;
}

/* The three children, looked up once. Both forwards index this List, so
   neither pays a name lookup per layer per step. */
static List _layers(Module model) {
  Module l1 = model.child("l1"), l2 = model.child("l2"),
         l3 = model.child("l3");
  return %($l1 $l2 $l3);
}

static Module _built(String directory, String name) {
  Module model = _mlp();
  model.load(%"$directory/$name");
  return model;
}

static Tensor _forward(List layers, Tensor x) =>
  Module.forward(layers[2].module(),
    Module.forward(layers[1].module(),
      Module.forward(layers[0].module(), x).relu()).relu());

static Tensor _affine(Module layer, Tensor x) {
  List parameters = layer.parameters();
  return x @ parameters[0].tensor().t() + parameters[1].tensor();
}

static Tensor _forward_explicit(List layers, Tensor x) =>
  _affine(layers[2].module(),
    _affine(layers[1].module(),
      _affine(layers[0].module(), x).relu()).relu());

static Tensor _apply(List layers, Tensor x, int native) =>
  native ? _forward(layers, x) : _forward_explicit(layers, x);

static double _evaluate(List layers, Tensor x, Tensor y, int native) {
  Scope.retain();
  defer Scope.release();
  Torch.inference_mode();
  return Tensor.mse_loss(_apply(layers, x, native), y).item().double();
}

/* One training step is one scope: the forward's temporaries, the graph,
   and the gradients all end with it, while the model and the optimizer
   live in the caller's scope. */
static void _step(List layers, Optimizer adam, Tensor x, Tensor y,
                  Tensor batches, long row, int native) {
  Scope.retain();
  defer Scope.release();
  Tensor pick = batches.select(0, row);
  adam.zero_grad();
  Tensor error = Tensor.mse_loss(_apply(layers, x.index_select(0, pick),
                                        native),
                                 y.index_select(0, pick));
  error.backward();
  adam.step();
}

static void _train(List layers, Optimizer adam, Tensor x, Tensor y,
                   Tensor batches, int count, int offset, int native,
                   int sample_every) {
  long rows = batches.size(0);
  for (int step = 0; step < count; step++) {
    _step(layers, adam, x, y, batches, (offset + step) % rows, native);
    if (sample_every > 0 && (step + 1) % sample_every == 0)
      Bench.sample("step", step + 1);
  }
}

/* The constant-mean predictor, one of the two baselines training must
   beat. A row of ones times the mean row broadcasts without relying on
   an implicit shape rule the two languages might differ on. */
static double _mean_baseline(Tensor y_train, Tensor y_val) {
  Scope.retain();
  defer Scope.release();
  Torch.inference_mode();
  Tensor mean = y_train.mean_dim(0, 1);
  long rows = y_val.size(0);
  Tensor column = Tensor.ones(%($rows 1), XT_FLOAT32);
  return Tensor.mse_loss(column @ mean, y_val).item().double();
}

static void _record_profile(void) {
  Bench.record_int("cfg_features", FEATURES);
  Bench.record_int("cfg_hidden1", HIDDEN1);
  Bench.record_int("cfg_hidden2", HIDDEN2);
  Bench.record_int("cfg_targets", TARGETS);
  Bench.record_int("cfg_batch", BATCH);
  Bench.record_int("cfg_updates", UPDATES);
  Bench.record("cfg_lr", LR);
  Bench.record_int("cfg_artifact_version", ARTIFACT_VERSION);
}

/* ---- check ---- */

static int _check(String artifacts, String out) {
  Map data = _artifact(artifacts, "tabular-data.pt");
  Map batches = _artifact(artifacts, "tabular-batches.pt");
  (void) _artifact(artifacts, "tabular-init.pt");
  Tensor x_train = data["data.x_train"].tensor();
  Tensor y_train = data["data.y_train"].tensor();
  Tensor x_val = data["data.x_val"].tensor();
  Tensor y_val = data["data.y_val"].tensor();
  Tensor rows = batches["batches"].tensor();

  /* One update with every value kept: the outputs, the loss, each
     gradient, and each parameter afterwards. The tolerances in the plan
     are stated on exactly these tensors. */
  Module model = _built(artifacts, "tabular-init.pt");
  List layers = _layers(model);
  Optimizer adam = Optimizer.adam(model, LR);
  Tensor pick = rows.select(0, 0);
  Tensor output = _forward(layers, x_train.index_select(0, pick));
  Tensor error = Tensor.mse_loss(output, y_train.index_select(0, pick));
  adam.zero_grad();
  error.backward();
  Map step1 = %{};
  step1["probe.output"] = output;
  step1["probe.loss"] = error;
  foreach (List pair, model.named_parameters()) {
    String name = pair[0].str();
    step1[%"grad.$name"] = pair[1].tensor().grad();
  }
  adam.step();
  foreach (List pair, model.named_parameters()) {
    String name = pair[0].str();
    step1[%"step1.$name"] = pair[1].tensor().clone();
  }
  Checkpoint.save(step1, %"$out/tabular-x2c-step1.pt");
  Bench.record("probe_loss", error.item().double());

  Module untrained = _built(artifacts, "tabular-init.pt");
  Bench.record("untrained_val_mse",
               _evaluate(_layers(untrained), x_val, y_val, 1));
  Bench.record("mean_val_mse", _mean_baseline(y_train, y_val));

  /* The full fixed profile with the native Linear forward. */
  Module trained = _built(artifacts, "tabular-init.pt");
  List trained_layers = _layers(trained);
  Optimizer trainer = Optimizer.adam(trained, LR);
  _train(trained_layers, trainer, x_train, y_train, rows, UPDATES, 0, 1, 0);
  Bench.record("trained_val_mse",
               _evaluate(trained_layers, x_val, y_val, 1));
  {
    Scope.retain();
    defer Scope.release();
    Torch.inference_mode();
    Map final = %{};
    foreach (List pair, trained.named_parameters()) {
      String name = pair[0].str();
      final[%"final.$name"] = pair[1].tensor().clone();
    }
    final["predictions"] = _forward(trained_layers, x_val).clone();
    Checkpoint.save(final, %"$out/tabular-x2c-final.pt");
  }

  /* The same training through the documented explicit forward. */
  Module explicit = _built(artifacts, "tabular-init.pt");
  List explicit_layers = _layers(explicit);
  _train(explicit_layers, Optimizer.adam(explicit, LR), x_train, y_train,
         rows, UPDATES, 0, 0, 0);
  Bench.record("explicit_val_mse",
               _evaluate(explicit_layers, x_val, y_val, 0));

  /* Uninterrupted against save, reload, and resume. The optimizer state
     crosses through the C++ archive, which is for x2c and C++ only. */
  Module resumed = _built(artifacts, "tabular-init.pt");
  List resumed_layers = _layers(resumed);
  Optimizer resume_adam = Optimizer.adam(resumed, LR);
  int half = UPDATES / 2;
  _train(resumed_layers, resume_adam, x_train, y_train, rows, half, 0, 1, 0);
  resumed.save(%"$out/tabular-x2c-resume.pt");
  resume_adam.save(%"$out/tabular-x2c-optimizer.pt");
  Module fresh = _mlp();
  fresh.load(%"$out/tabular-x2c-resume.pt");
  List fresh_layers = _layers(fresh);
  Optimizer fresh_adam = Optimizer.adam(fresh, LR);
  fresh_adam.load(%"$out/tabular-x2c-optimizer.pt");
  _train(fresh_layers, fresh_adam, x_train, y_train, rows, UPDATES - half,
         half, 1, 0);
  Bench.record("resumed_val_mse", _evaluate(fresh_layers, x_val, y_val, 1));

  /* Batched prediction: one request scope, inference mode, three sizes. */
  int sizes[3] = { 1, 32, 256 };
  for (int i = 0; i < 3; i++) {
    int size = sizes[i];
    Tensor requests = batches[%"requests.$size"].tensor();
    long count = requests.size(0);
    double total = 0.0;
    for (long index = 0; index < count; index++) {
      Scope.retain();
      defer Scope.release();
      Torch.inference_mode();
      Tensor batch = x_val.index_select(0, requests.select(0, index));
      total += _forward(trained_layers, batch).abs().sum().item().double();
    }
    char name[32];
    snprintf(name, sizeof(name), "predict%d_checksum", size);
    Bench.record(name, total);
  }
  return 0;
}

/* ---- time ---- */

static int _time_predict(String artifacts, String out, int size,
                         int requests) {
  Map data = _artifact(artifacts, "tabular-data.pt");
  Map batches = _artifact(artifacts, "tabular-batches.pt");
  Tensor x_val = data["data.x_val"].tensor();
  Tensor rows = batches[%"requests.$size"].tensor();
  long available = rows.size(0);
  Module model = _built(artifacts, "tabular-init.pt");
  model.eval();
  List layers = _layers(model);

  for (int index = 0; index < WARMUP; index++) {
    Scope.retain();
    defer Scope.release();
    Torch.inference_mode();
    (void) _forward(layers,
                    x_val.index_select(0, rows.select(0, index % available)));
  }

  double checksum = 0.0;
  double start = Bench.now();
  for (int index = 0; index < requests; index++) {
    Scope.retain();
    defer Scope.release();
    Torch.inference_mode();
    Tensor batch = x_val.index_select(0, rows.select(0, index % available));
    checksum += _forward(layers, batch).abs().sum().item().double();
  }
  double seconds = Bench.now() - start;
  Bench.record_int("requests", requests);
  Bench.record("steady_seconds", seconds);
  Bench.record("requests_per_second", requests / seconds);
  Bench.record("checksum", checksum);
  return 0;
}

static int _time(String artifacts, String out, String variant, int updates) {
  Bench.record_text("variant", variant);
  Bench.record_int("threads", Torch.num_threads());
  if (!strncmp(variant, "predict", 7))
    return _time_predict(artifacts, out, atoi(variant + 7), updates);

  int native = !strcmp(variant, "native");
  Map data = _artifact(artifacts, "tabular-data.pt");
  Map batches = _artifact(artifacts, "tabular-batches.pt");
  Tensor x_train = data["data.x_train"].tensor();
  Tensor y_train = data["data.y_train"].tensor();
  Tensor rows = batches["batches"].tensor();

  /* Warm the lazy kernels and the Adam state, then start again from the
     saved initial parameters: warmup must not change the problem. */
  Module warm = _built(artifacts, "tabular-init.pt");
  double warm_start = Bench.now();
  _train(_layers(warm), Optimizer.adam(warm, LR), x_train, y_train, rows,
         WARMUP, 0, native, 0);
  Bench.record("warmup_seconds", Bench.now() - warm_start);

  Module model = _built(artifacts, "tabular-init.pt");
  List layers = _layers(model);
  Optimizer adam = Optimizer.adam(model, LR);
  double start = Bench.now();
  _train(layers, adam, x_train, y_train, rows, updates, 0, native, 0);
  double seconds = Bench.now() - start;
  Bench.record_int("updates", updates);
  Bench.record("steady_seconds", seconds);
  Bench.record("updates_per_second", updates / seconds);
  Bench.record("final_train_loss",
               _evaluate(layers, data["data.x_val"].tensor(),
                         data["data.y_val"].tensor(), native));
  return 0;
}

/* ---- memory ---- */

/* Profile 1: steady training and inference at a fixed shape, with the
   model, data, and optimizer outside the step. */
static void _memory_steady(String artifacts, Map data, Map batches,
                           int steps) {
  Tensor x_train = data["data.x_train"].tensor();
  Tensor y_train = data["data.y_train"].tensor();
  Tensor x_val = data["data.x_val"].tensor();
  Tensor rows = batches["batches"].tensor();
  Module model = _built(artifacts, "tabular-init.pt");
  List layers = _layers(model);
  Optimizer adam = Optimizer.adam(model, LR);
  Bench.sample("setup", 0);
  _train(layers, adam, x_train, y_train, rows, WARMUP, 0, 1, 0);
  Bench.sample("warm", 0);
  int every = steps / 16 > 0 ? steps / 16 : 1;
  _train(layers, adam, x_train, y_train, rows, steps, 0, 1, every);
  Bench.sample("trained", steps);

  Tensor requests = batches["requests.32"].tensor();
  long available = requests.size(0);
  for (int index = 0; index < steps; index++) {
    Scope.retain();
    {
      defer Scope.release();
      Torch.inference_mode();
      (void) _forward(layers, x_val.index_select(
                                0, requests.select(0, index % available)));
    }
    if ((index + 1) % every == 0) Bench.sample("request", index + 1);
  }
  Bench.sample("served", steps);
}

/* Profile 3: a useful survivor. A view keeps its whole backing storage
   alive on purpose; the cloned result does not. Scope.move carries one
   allocation, the wrapper, past the scope that created it. */
static void _memory_survivor(void) {
  Scope survivor = NULL, cloned_owner = NULL;
  Tensor view = NULL, cloned = NULL;
  Bench.sample("before", 0);
  Scope.retain();
  {
    defer Scope.release();
    Tensor big = Tensor.randn(%(4194304 4), XT_FLOAT32);
    Bench.sample("allocated", 0);
    view = big.narrow(0, 0, 16);
    cloned = big.narrow(0, 0, 16).clone();
    Scope.move(view, &survivor);
    Scope.move(cloned, &cloned_owner);
  }
  Bench.sample("view-survives", 0);
  Bench.record("view_sum", view.sum().item().double());
  Bench.record("clone_sum", cloned.sum().item().double());
  Scope.destroy(survivor);
  Bench.sample("view-released", 0);
  Bench.record("clone_sum_after", cloned.sum().item().double());
  Scope.destroy(cloned_owner);
  Bench.sample("clone-released", 0);
}

/* Profile 5: repeated create, train, save, load, destroy over one
   overwritten checkpoint, with a deliberate bad shape every 100 requests
   and ordinary work after it. */
static void _memory_lifetime(String artifacts, String out, Map data,
                             Map batches, int cycles) {
  Tensor x_train = data["data.x_train"].tensor();
  Tensor y_train = data["data.y_train"].tensor();
  Tensor x_val = data["data.x_val"].tensor();
  Tensor rows = batches["batches"].tensor();
  String checkpoint = %"$out/tabular-x2c-cycle.pt";
  int requests = 0, every = cycles / 16 > 0 ? cycles / 16 : 1;
  for (int cycle = 0; cycle < cycles; cycle++) {
    Scope.retain();
    {
      defer Scope.release();
      Module model = _built(artifacts, "tabular-init.pt");
      List layers = _layers(model);
      Optimizer adam = Optimizer.adam(model, LR);
      Scheduler schedule = Scheduler.step_lr(adam, 10, 0.5);
      _train(layers, adam, x_train, y_train, rows, 20, cycle * 20, 1, 0);
      schedule.step();
      model.save(checkpoint);
      Module reloaded = _mlp();
      reloaded.load(checkpoint);
      List reloaded_layers = _layers(reloaded);
      requests += 20;
      if (requests % 100 == 0) {
        try {
          Scope.retain();
          defer Scope.release();
          (void) _forward(reloaded_layers,
                          Tensor.randn(%(4 129), XT_FLOAT32));
        }
        catch %(bad-state (library "torch") *detail): {
          Bench.record_int("caught_bad_shape", 1);
        }
        /* Valid work still runs, and the mode is what it was. */
        reloaded.eval();
        {
          Scope.retain();
          defer Scope.release();
          Torch.inference_mode();
          (void) _forward(reloaded_layers, x_val.narrow(0, 0, 4));
        }
        reloaded.train();
        Bench.record_int("mode_after_error", reloaded.is_training());
      }
    }
    if ((cycle + 1) % every == 0) Bench.sample("cycle", cycle + 1);
  }
  Bench.sample("cycles-done", cycles);
}

/* Profile 6: the positive control. Outputs and their graphs are retained
   on purpose up to 128 MiB, so the measurement is shown to see a known
   problem before any result is called healthy. */
static void _memory_control(String artifacts, Map data, int steps) {
  Tensor x_val = data["data.x_val"].tensor();
  Module model = _built(artifacts, "tabular-init.pt");
  List layers = _layers(model);
  int every = steps / 16 > 0 ? steps / 16 : 1;
  Scope.retain();
  {
    defer Scope.release();
    Array retained = %[];
    Tensor block = x_val.narrow(0, 0, 2048);
    long held = 0, capacity = RETAIN_CAP_BYTES;
    int count = 0;
    for (int index = 0; index < steps; index++) {
      Tensor output = _forward(layers, block) * 1.0;
      held += (output.numel() + block.numel()) * 4;
      if (held > capacity) {
        Bench.record_int("control_capped_at", index);
        break;
      }
      retained.push(%($output));
      count++;
      if (count % every == 0) Bench.sample("retained", count);
    }
    Bench.record_int("control_retained", count);
    Bench.sample("retained-peak", count);
  }
  Bench.sample("released", 0);
}

static int _memory(String artifacts, String out, int profile, int steps) {
  Bench.sample("baseline", 0);
  Map data = _artifact(artifacts, "tabular-data.pt");
  Map batches = _artifact(artifacts, "tabular-batches.pt");
  Bench.sample("loaded", 0);
  switch (profile) {
    case 1: _memory_steady(artifacts, data, batches, steps); break;
    case 3: _memory_survivor(); break;
    case 5: _memory_lifetime(artifacts, out, data, batches, steps); break;
    case 6: _memory_control(artifacts, data, steps); break;
    default:
      raise %(bad-arg (reason "no such memory profile") (profile $profile));
  }
  Bench.sample("final", 0);
  Bench.flush();
  return 0;
}

#pragma public

int main(int argc, char **argv) {
  Scope.retain();
  defer Scope.release();
  if (argc < 4) {
    fprintf(stderr, "usage: tabular <check|time|memory> <artifacts> <out>"
                    " [variant] [count]\n");
    return 2;
  }
  const char *threads = getenv("X2C_TORCH_THREADS");
  Torch.set_num_threads(threads ? atoi(threads) : 1);
  Torch.manual_seed(0);
  Bench.begin(4096);
  Bench.record_text("language", "x2c");
  Bench.record_text("torch_version", Torch.version());
  _record_profile();
  Bench.record_int("threads", Torch.num_threads());

  String artifacts = String.new(argv[2]), out = String.new(argv[3]);
  if (!strcmp(argv[1], "check")) return _check(artifacts, out);
  if (!strcmp(argv[1], "time"))
    return _time(artifacts, out, String.new(argv[4]), atoi(argv[5]));
  if (!strcmp(argv[1], "memory"))
    return _memory(artifacts, out, atoi(argv[4]), atoi(argv[5]));
  fprintf(stderr, "tabular: no mode %s\n", argv[1]);
  return 2;
}
