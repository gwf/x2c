/*  sequence.x -- Application 3: stateful forecasting with truncated
    backpropagation.

    A tanh recurrent cell written out of three Linear applications, over
    streams a driven nonlinear system produced. Each window is one scope:
    the graph spans the window on purpose and is released with it, and the
    detached hidden state is the one allocation carried across.

    `Scope.move` carries that state's wrapper into a scope this file owns,
    and the previous window's carrier is destroyed once the new state
    exists. That is the caller obligation the memory profile measures, not
    a framework.

      sequence check   <artifacts> <out>
      sequence time    <artifacts> <out> <window8|window32|window128> <count>
      sequence memory  <artifacts> <out> 4 <windows>
*/

import "torch" with Torch, Tensor, Module, Optimizer, Checkpoint;

#include <stdlib.h>
#include <string.h>
#include "bench.x"

#define ARTIFACT_VERSION 1
#define OBSERVED 8
#define HIDDEN 64
#define WINDOW 32
#define WINDOWS 512
#define LR 0.001
#define WARMUP 50

#pragma private

/* The surviving hidden state and the scope that owns it. */
typedef struct Carry {
  Scope owner;
  Tensor state;
} Carry;

static Map _artifact(String directory, String name) {
  String path = %"$directory/$name";
  Map values = Checkpoint.load(path);
  long version = values["meta.version"].tensor().item().integer();
  if (version != ARTIFACT_VERSION)
    raise %(bad-state (artifact $name) (version $version)
            (reason "artifact version does not match this program"));
  return values;
}

static Module _rnn(void) {
  Module model = Module.composed();
  model.register("ih", Module.linear(OBSERVED, HIDDEN));
  model.register("hh", Module.linear_bias(HIDDEN, HIDDEN, 0));
  model.register("out", Module.linear(HIDDEN, OBSERVED));
  return model;
}

static List _layers(Module model) {
  Module ih = model.child("ih"), hh = model.child("hh"),
         out = model.child("out");
  return %($ih $hh $out);
}

static Module _built(String directory, String name) {
  Module model = _rnn();
  model.load(%"$directory/$name");
  return model;
}

static Tensor _cell(List layers, Tensor x, Tensor h) =>
  (Module.forward(layers[0].module(), x) +
   Module.forward(layers[1].module(), h)).tanh();

static Tensor _predict(List layers, Tensor h) =>
  Module.forward(layers[2].module(), h);

static Tensor _zero_state(long streams) {
  long hidden = HIDDEN;
  return Tensor.zeros(%($streams $hidden), XT_FLOAT32);
}

/* Takes ownership of `state` for the caller's next window and releases
   the state the previous window left behind. */
static void _carry(Carry *carry, Tensor state) {
  Scope replacement = NULL;
  Scope.move(state, &replacement);
  if (carry.owner) Scope.destroy(carry.owner);
  carry.owner = replacement;
  carry.state = state;
}

static void _release_carry(Carry *carry) {
  if (carry.owner) Scope.destroy(carry.owner);
  carry.owner = NULL;
  carry.state = NULL;
}

/* One truncation window: the loss over its steps and the state it ends
   with. The caller owns the scope this runs in. */
static Tensor _window(List layers, Tensor inputs, Tensor targets, Tensor h,
                      Tensor *final_state) {
  long steps = inputs.size(1);
  Tensor total = NULL;
  for (long t = 0; t < steps; t++) {
    h = _cell(layers, inputs.select(1, t), h);
    Tensor loss = Tensor.mse_loss(_predict(layers, h), targets.select(1, t));
    total = total ? total + loss : loss;
  }
  *final_state = h;
  double count = steps;
  return total / count;
}

static void _train(List layers, Optimizer adam, Tensor streams, int count,
                   int window, int offset, int microbatches,
                   int sample_every) {
  long stream_count = streams.size(0), steps = streams.size(1);
  int per_epoch = (int) ((steps - 1) / window);
  Carry carry = { NULL, NULL };
  defer _release_carry(&carry);
  for (int index = 0; index < count; index++) {
    int position = (offset + index) % per_epoch;
    long start = (long) position * window;
    Scope.retain();
    {
      defer Scope.release();
      /* A stream boundary resets the state; a truncation boundary keeps
         it and detaches it. */
      if (position == 0 || !carry.state)
        _carry(&carry, _zero_state(stream_count));
      Tensor inputs = streams.slice(1, start, start + window, 1);
      Tensor targets = streams.slice(1, start + 1, start + window + 1, 1);
      adam.zero_grad();
      Tensor ended = NULL;
      if (microbatches <= 1) {
        Tensor error = _window(layers, inputs, targets, carry.state, &ended);
        error.backward();
      }
      else {
        /* Gradient accumulation: one backward per microbatch, one update. */
        long size = stream_count / microbatches;
        List pieces = %();
        double scale = microbatches;
        for (int m = 0; m < microbatches; m++) {
          Tensor piece = NULL;
          Tensor part = _window(layers, inputs.narrow(0, m * size, size),
                                targets.narrow(0, m * size, size),
                                carry.state.narrow(0, m * size, size),
                                &piece);
          (part / scale).backward();
          Tensor detached = piece.detach();
          pieces = pieces.append(%($detached));
        }
        ended = Tensor.cat(pieces, 0);
      }
      adam.step();
      _carry(&carry, ended.detach());
    }
    if (sample_every > 0 && (index + 1) % sample_every == 0)
      Bench.sample("window", index + 1);
  }
}

/* Held-out MSE of the next observation, with the state carried through
   the whole stream under inference mode. */
static double _score(List layers, Tensor streams) {
  Scope.retain();
  defer Scope.release();
  Torch.inference_mode();
  long count = streams.size(0), steps = streams.size(1);
  Tensor h = _zero_state(count);
  double total = 0.0;
  for (long t = 0; t + 1 < steps; t++) {
    h = _cell(layers, streams.select(1, t), h);
    total += Tensor.mse_loss(_predict(layers, h),
                             streams.select(1, t + 1)).item().double();
  }
  return total / (double) (steps - 1);
}

/* The constant-mean and last-value predictors. Both are reported even
   when last-value wins. */
static void _baselines(Tensor train, Tensor val) {
  Scope.retain();
  defer Scope.release();
  Torch.inference_mode();
  long steps = val.size(1);
  Tensor target = val.slice(1, 1, steps, 1);
  Tensor mean = train.mean_dim(0, 0).mean_dim(0, 0);
  Bench.record("mean_val_mse",
               (target - mean).pow(2.0).mean().item().double());
  Bench.record("last_value_val_mse",
               Tensor.mse_loss(val.slice(1, 0, steps - 1, 1),
                               target).item().double());
}

static void _record_profile(void) {
  Bench.record_int("cfg_observed", OBSERVED);
  Bench.record_int("cfg_hidden", HIDDEN);
  Bench.record_int("cfg_window", WINDOW);
  Bench.record_int("cfg_windows", WINDOWS);
  Bench.record("cfg_lr", LR);
  Bench.record_int("cfg_artifact_version", ARTIFACT_VERSION);
}

/* ---- check ---- */

static int _check(String artifacts, String out) {
  Map data = _artifact(artifacts, "sequence-data.pt");
  Tensor train = data["data.train"].tensor();
  Tensor val = data["data.val"].tensor();
  long streams = train.size(0);

  Module model = _built(artifacts, "sequence-init.pt");
  List layers = _layers(model);
  Optimizer adam = Optimizer.adam(model, LR);
  Tensor ended = NULL;
  Tensor loss = _window(layers, train.slice(1, 0, WINDOW, 1),
                        train.slice(1, 1, WINDOW + 1, 1),
                        _zero_state(streams), &ended);
  adam.zero_grad();
  loss.backward();
  Map step1 = %{};
  step1["probe.loss"] = loss;
  step1["probe.state"] = ended.detach();
  foreach (List pair, model.named_parameters()) {
    String name = pair[0].str();
    step1[%"grad.$name"] = pair[1].tensor().grad();
  }
  adam.step();
  foreach (List pair, model.named_parameters()) {
    String name = pair[0].str();
    step1[%"step1.$name"] = pair[1].tensor().clone();
  }
  Checkpoint.save(step1, %"$out/sequence-x2c-step1.pt");
  Bench.record("probe_loss", loss.item().double());

  Module untrained = _built(artifacts, "sequence-init.pt");
  Bench.record("untrained_val_mse", _score(_layers(untrained), val));
  _baselines(train, val);

  Module trained = _built(artifacts, "sequence-init.pt");
  List trained_layers = _layers(trained);
  _train(trained_layers, Optimizer.adam(trained, LR), train, WINDOWS, WINDOW,
         0, 1, 0);
  Bench.record("trained_val_mse", _score(trained_layers, val));
  {
    Scope.retain();
    defer Scope.release();
    Map final = %{};
    foreach (List pair, trained.named_parameters()) {
      String name = pair[0].str();
      final[%"final.$name"] = pair[1].tensor().clone();
    }
    Checkpoint.save(final, %"$out/sequence-x2c-final.pt");
  }

  Module resumed = _built(artifacts, "sequence-init.pt");
  List resumed_layers = _layers(resumed);
  Optimizer resume_adam = Optimizer.adam(resumed, LR);
  int half = WINDOWS / 2;
  _train(resumed_layers, resume_adam, train, half, WINDOW, 0, 1, 0);
  resumed.save(%"$out/sequence-x2c-resume.pt");
  resume_adam.save(%"$out/sequence-x2c-optimizer.pt");
  Module fresh = _rnn();
  fresh.load(%"$out/sequence-x2c-resume.pt");
  List fresh_layers = _layers(fresh);
  Optimizer fresh_adam = Optimizer.adam(fresh, LR);
  fresh_adam.load(%"$out/sequence-x2c-optimizer.pt");
  _train(fresh_layers, fresh_adam, train, WINDOWS - half, WINDOW, half, 1, 0);
  Bench.record("resumed_val_mse", _score(fresh_layers, val));

  int sweep[3] = { 8, 32, 128 };
  for (int i = 0; i < 3; i++) {
    Module swept = _built(artifacts, "sequence-init.pt");
    List swept_layers = _layers(swept);
    _train(swept_layers, Optimizer.adam(swept, LR), train, 64, sweep[i], 0,
           1, 0);
    char name[32];
    snprintf(name, sizeof(name), "window%d_val_mse", sweep[i]);
    Bench.record(name, _score(swept_layers, val));
  }
  return 0;
}

/* ---- time ---- */

static int _time(String artifacts, String out, String variant, int count) {
  Bench.record_text("variant", variant);
  Bench.record_int("threads", Torch.num_threads());
  int window = atoi(variant + 6);
  Map data = _artifact(artifacts, "sequence-data.pt");
  Tensor train = data["data.train"].tensor();

  Module warm = _built(artifacts, "sequence-init.pt");
  double warm_start = Bench.now();
  _train(_layers(warm), Optimizer.adam(warm, LR), train, WARMUP, window, 0,
         1, 0);
  Bench.record("warmup_seconds", Bench.now() - warm_start);

  Module model = _built(artifacts, "sequence-init.pt");
  List layers = _layers(model);
  double start = Bench.now();
  _train(layers, Optimizer.adam(model, LR), train, count, window, 0, 1, 0);
  double seconds = Bench.now() - start;
  Bench.record_int("windows", count);
  Bench.record_int("window_length", window);
  Bench.record("steady_seconds", seconds);
  Bench.record("windows_per_second", count / seconds);
  Bench.record("steps_per_second", (double) count * window / seconds);
  return 0;
}

/* ---- memory ---- */

static int _memory(String artifacts, String out, int profile, int count) {
  if (profile != 4)
    raise %(bad-arg (reason "no such memory profile") (profile $profile));
  Bench.sample("baseline", 0);
  Map data = _artifact(artifacts, "sequence-data.pt");
  Tensor train = data["data.train"].tensor();
  Bench.sample("loaded", 0);

  int sweep[3] = { 8, 32, 128 };
  for (int i = 0; i < 3; i++) {
    Module model = _built(artifacts, "sequence-init.pt");
    Bench.sample("window-start", sweep[i]);
    _train(_layers(model), Optimizer.adam(model, LR), train, count, sweep[i],
           0, 1, 0);
    Bench.sample("window-done", sweep[i]);
  }

  Module model = _built(artifacts, "sequence-init.pt");
  List layers = _layers(model);
  Bench.sample("accumulate-start", 4);
  _train(layers, Optimizer.adam(model, LR), train, count, WINDOW, 0, 4, 0);
  Bench.sample("accumulate-done", 4);
  Tensor val = data["data.val"].tensor();
  Bench.record("accumulated_val_mse", _score(layers, val));
  Bench.sample("final", 0);
  Bench.flush();
  return 0;
}

#pragma public

int main(int argc, char **argv) {
  Scope.retain();
  defer Scope.release();
  if (argc < 4) {
    fprintf(stderr, "usage: sequence <check|time|memory> <artifacts> <out>"
                    " [variant] [count]\n");
    return 2;
  }
  const char *threads = getenv("X2C_TORCH_THREADS");
  Torch.set_num_threads(threads ? atoi(threads) : 1);
  /* Inter-op threads are fixed before any work, so the only parallelism
     either language uses is the intra-op pool the runner sets. */
  Torch.set_num_interop_threads(1);
  Torch.manual_seed(0);
  Bench.begin(4096);
  Bench.record_text("language", "x2c");
  Bench.record_text("torch_version", Torch.version());
  _record_profile();
  Bench.record_int("threads", Torch.num_threads());
  Bench.record_int("interop_threads", Torch.num_interop_threads());

  String artifacts = String.new(argv[2]), out = String.new(argv[3]);
  if (!strcmp(argv[1], "check")) return _check(artifacts, out);
  if (!strcmp(argv[1], "time"))
    return _time(artifacts, out, String.new(argv[4]), atoi(argv[5]));
  if (!strcmp(argv[1], "memory"))
    return _memory(artifacts, out, atoi(argv[4]), atoi(argv[5]));
  fprintf(stderr, "sequence: no mode %s\n", argv[1]);
  return 2;
}
