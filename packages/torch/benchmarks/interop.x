/*  interop.x -- The diagnostic that explains the application results.

    One request is a chain of affine and activation steps on one tensor:
    `y = relu(y * a + b)`, repeated. Element counts of 1, 64, 4,096, and
    65,536 and 16, 128, or 512 operations per request separate the cost of
    reaching a kernel from the cost of the kernel.

    interop.cpp runs the identical ATen sequence with no wrapper at all, so
    the three programs bound host cost from both sides. It is a diagnostic,
    not another application framework.

      interop check   <artifacts> <out>
      interop time    <artifacts> <out>
                      <chain|freed|subscope|e<count>o<ops>> <requests>
      interop memory  <artifacts> <out> 4 <requests>
      interop attribute <artifacts> <out> <elements> <requests>
                        [natural|freed|subscope|all]
*/

import "torch" with Torch, Tensor, Checkpoint;

#include <stdlib.h>
#include <string.h>
#include "bench.x"

#define ARTIFACT_VERSION 1

#pragma private

static const int interop_elements[4] = { 1, 64, 4096, 65536 };
static const int interop_operations[3] = { 16, 128, 512 };

static Map _artifact(String directory, String name) {
  String path = %"$directory/$name";
  Map values = Checkpoint.load(path);
  long version = values["meta.version"].tensor().item().integer();
  if (version != ARTIFACT_VERSION)
    raise %(bad-state (artifact $name) (version $version)
            (reason "artifact version does not match this program"));
  return values;
}

/* One request. Out-of-place throughout: every step allocates its result,
   which is the behavior being measured. */
static double _chain(Tensor x, Tensor a, Tensor b, int operations) {
  Scope.retain();
  defer Scope.release();
  Torch.inference_mode();
  Tensor y = x;
  for (int i = 0; i < operations; i++) y = (y * a + b).relu();
  return y.sum().item().double();
}

static Tensor _input(Map values, String prefix, int count) =>
  values[%"$prefix.$count"].tensor();

/* Checks and timings use the same existing lifetime variants. Sampling is
   enabled only by attribute mode, never during ordinary timing. */
static int chain_lifetime;
static int interop_observe;
static double _chain_freed(Tensor, Tensor, Tensor, int);
static double _chain_subscope(Tensor, Tensor, Tensor, int);

static double _timed_chain(Tensor x, Tensor a, Tensor b, int operations) {
  if (chain_lifetime == 1) return _chain_freed(x, a, b, operations);
  if (chain_lifetime == 2) return _chain_subscope(x, a, b, operations);
  return _chain(x, a, b, operations);
}

static int _check(String artifacts, String out) {
  Map values = _artifact(artifacts, "interop-init.pt");
  for (int e = 0; e < 4; e++) {
    for (int o = 0; o < 3; o++) {
      int count = interop_elements[e], operations = interop_operations[o];
      double result = _timed_chain(_input(values, "x", count),
                             _input(values, "a", count),
                             _input(values, "b", count), operations);
      char name[48];
      snprintf(name, sizeof(name), "chain_e%d_o%d", count, operations);
      Bench.record(name, result);
    }
  }
  return 0;
}

static int _time(String artifacts, String out, String variant, int requests) {
  Bench.record_text("variant", variant);
  Bench.record_int("threads", Torch.num_threads());
  Map values = _artifact(artifacts, "interop-init.pt");

  /* `chain` sweeps every pair; e<count>o<ops> times one pair alone. */
  int single_elements = 0, single_operations = 0;
  if (strcmp(variant, "chain")) {
    const char *split = strchr(variant, 'o');
    if (!split) raise %(bad-arg (reason "variant is chain or e<n>o<k>"));
    single_elements = atoi(variant + 1);
    single_operations = atoi(split + 1);
  }

  double total_seconds = 0.0;
  for (int e = 0; e < 4; e++) {
    for (int o = 0; o < 3; o++) {
      int count = interop_elements[e], operations = interop_operations[o];
      if (single_elements &&
          (count != single_elements || operations != single_operations))
        continue;
      Tensor x = _input(values, "x", count), a = _input(values, "a", count),
             b = _input(values, "b", count);
      for (int i = 0; i < 8; i++) (void) _timed_chain(x, a, b, operations);
      double result = 0.0;
      double start = Bench.now();
      for (int i = 0; i < requests; i++)
        result += _timed_chain(x, a, b, operations);
      double seconds = Bench.now() - start;
      total_seconds += seconds;
      char name[48];
      snprintf(name, sizeof(name), "seconds_e%d_o%d", count, operations);
      Bench.record(name, seconds);
      snprintf(name, sizeof(name), "ns_per_op_e%d_o%d", count, operations);
      Bench.record(name, seconds * 1e9 / ((double) requests * operations));
      snprintf(name, sizeof(name), "result_e%d_o%d", count, operations);
      Bench.record(name, result);
    }
  }
  Bench.record_int("requests", requests);
  Bench.record("steady_seconds", total_seconds);
  return 0;
}

/* ---- attribute ----

   The same chain under three lifetimes, so the cost of keeping every
   intermediate alive can be separated from the cost of the kernels.

   `natural`  one scope per request, which is the documented idiom: every
              intermediate lives until the request ends.
   `freed`    one scope per request, but each step releases the value it
              replaced with `Tensor.free`, which is the caller-side remedy
              that keeps the single scope.
   `subscope` one scope per operation, carrying only the running value out
              with `Scope.move`, which is the finest granularity that
              still produces the same result.

   Each phase reports its time, the most tensor handles alive at once, and
   the process footprint at the moment the chain completed, while the
   scope is still open. interop.cpp times the identical sequence with no
   wrapper at all and bounds all three from below.
*/

static uint64_t interop_peak_handles = 0;
static uint64_t interop_peak_footprint = 0;

static void _note_live(void) {
  uint64_t live = xb_handles_live(XT_HANDLE_TENSOR);
  if (live > interop_peak_handles) interop_peak_handles = live;
  uint64_t bytes = xb_footprint();
  if (bytes > interop_peak_footprint) interop_peak_footprint = bytes;
}

static double _chain_natural(Tensor x, Tensor a, Tensor b, int operations) {
  Scope.retain();
  defer Scope.release();
  Torch.inference_mode();
  Tensor y = x;
  for (int i = 0; i < operations; i++) y = (y * a + b).relu();
  if (interop_observe) _note_live();
  return y.sum().item().double();
}

static double _chain_freed(Tensor x, Tensor a, Tensor b, int operations) {
  Scope.retain();
  defer Scope.release();
  Torch.inference_mode();
  Tensor y = x;
  for (int i = 0; i < operations; i++) {
    Tensor next = (y * a + b).relu();
    /* The first value is the caller's input and is not ours to release. */
    if (i > 0) (void) y.free();
    y = next;
  }
  if (interop_observe) _note_live();
  return y.sum().item().double();
}

static double _chain_subscope(Tensor x, Tensor a, Tensor b, int operations) {
  Scope owner = NULL;
  Tensor y = x;
  for (int i = 0; i < operations; i++) {
    Scope replacement = NULL;
    Scope.retain();
    {
      defer Scope.release();
      Torch.inference_mode();
      y = (y * a + b).relu();
      Scope.move(y, &replacement);
    }
    if (owner) Scope.destroy(owner);
    owner = replacement;
  }
  if (interop_observe) _note_live();
  double total;
  Scope.retain();
  {
    defer Scope.release();
    Torch.inference_mode();
    total = y.sum().item().double();
  }
  if (owner) Scope.destroy(owner);
  return total;
}

static double _shape(int shape, Tensor x, Tensor a, Tensor b, int ops) {
  if (shape == 0) return _chain_natural(x, a, b, ops);
  if (shape == 1) return _chain_freed(x, a, b, ops);
  return _chain_subscope(x, a, b, ops);
}

static int _attribute(String artifacts, String out, int elements,
                      int requests, String shape) {
  interop_observe = 1;
  Map values = _artifact(artifacts, "interop-init.pt");
  Bench.record_int("attr_elements", elements);
  Bench.record_int("attr_requests", requests);
  Bench.record_int("counters_enabled", xb_handles_enabled());
  Tensor x = _input(values, "x", elements), a = _input(values, "a", elements),
         b = _input(values, "b", elements);
  const char *names[3] = { "natural", "freed", "subscope" };
  for (int s = 0; s < 3; s++) {
    if (strcmp(shape, "all") && strcmp(shape, names[s])) continue;
    for (int o = 0; o < 3; o++) {
      int operations = interop_operations[o];
      for (int i = 0; i < 4; i++) (void) _shape(s, x, a, b, operations);
      interop_peak_handles = 0;
      interop_peak_footprint = 0;
      double result = 0.0;
      double start = Bench.now();
      for (int i = 0; i < requests; i++)
        result += _shape(s, x, a, b, operations);
      double seconds = Bench.now() - start;
      char name[64];
      snprintf(name, sizeof(name), "attr_%s_o%d_seconds", names[s],
               operations);
      Bench.record(name, seconds);
      snprintf(name, sizeof(name), "attr_%s_o%d_ns_per_step", names[s],
               operations);
      Bench.record(name, seconds * 1e9 / ((double) requests * operations));
      snprintf(name, sizeof(name), "attr_%s_o%d_peak_handles", names[s],
               operations);
      Bench.record_int(name, (long) interop_peak_handles);
      snprintf(name, sizeof(name), "attr_%s_o%d_peak_bytes", names[s],
               operations);
      Bench.record(name, (double) interop_peak_footprint);
      snprintf(name, sizeof(name), "attr_%s_o%d_result", names[s],
               operations);
      Bench.record(name, result);
    }
  }
  return 0;
}

static int _memory(String artifacts, String out, int profile, int requests) {
  if (profile != 4)
    raise %(bad-arg (reason "no such memory profile") (profile $profile));
  Bench.sample("baseline", 0);
  Map values = _artifact(artifacts, "interop-init.pt");
  Bench.sample("loaded", 0);
  int count = 65536;
  Tensor x = _input(values, "x", count), a = _input(values, "a", count),
         b = _input(values, "b", count);
  for (int o = 0; o < 3; o++) {
    int operations = interop_operations[o];
    Bench.sample("chain-start", operations);
    for (int i = 0; i < requests; i++) (void) _chain(x, a, b, operations);
    Bench.sample("chain-done", operations);
  }
  /* The same total work split into shorter scopes: the chain is broken
     into blocks of 16 operations, each its own scope, with only the
     running value carried forward. */
  Scope owner = NULL;
  Tensor y = x;
  Bench.sample("short-scope-start", 16);
  for (int block = 0; block < 512 / 16; block++) {
    Scope replacement = NULL;
    Scope.retain();
    {
      defer Scope.release();
      Torch.inference_mode();
      for (int i = 0; i < 16; i++) y = (y * a + b).relu();
      Scope.move(y, &replacement);
    }
    if (owner) Scope.destroy(owner);
    owner = replacement;
  }
  Bench.sample("short-scope-done", 16);
  Bench.record("short_scope_result", y.sum().item().double());
  if (owner) Scope.destroy(owner);
  Bench.sample("final", 0);
  Bench.flush();
  return 0;
}

#pragma public

int main(int argc, char **argv) {
  Scope.retain();
  defer Scope.release();
  if (argc < 4) {
    fprintf(stderr, "usage: interop <check|time|memory> <artifacts> <out>"
                    " [variant] [count]\n");
    return 2;
  }
  const char *threads = getenv("X2C_TORCH_THREADS");
  Torch.set_num_threads(threads ? atoi(threads) : 1);
  /* Inter-op threads are fixed before any work, so the only parallelism
     either language uses is the intra-op pool the runner sets. */
  Torch.set_num_interop_threads(1);
  Bench.begin(1024);
  Bench.record_text("language", "x2c");
  Bench.record_text("torch_version", Torch.version());
  Bench.record_text("counters", xb_handles_enabled() ? "on" : "off");
  Bench.record_int("cfg_artifact_version", ARTIFACT_VERSION);
  Bench.record_int("threads", Torch.num_threads());
  Bench.record_int("interop_threads", Torch.num_interop_threads());

  if (argc > 4 && !strcmp(argv[4], "freed")) chain_lifetime = 1;
  if (argc > 4 && !strcmp(argv[4], "subscope")) chain_lifetime = 2;
  Bench.record_text("lifetime", chain_lifetime == 1 ? "freed" :
                    chain_lifetime == 2 ? "subscope" : "natural");
  String artifacts = String.new(argv[2]), out = String.new(argv[3]);
  if (!strcmp(argv[1], "check")) return _check(artifacts, out);
  if (!strcmp(argv[1], "time"))
    return _time(artifacts, out, chain_lifetime ? "chain" :
                 String.new(argv[4]), atoi(argv[5]));
  if (!strcmp(argv[1], "memory"))
    return _memory(artifacts, out, atoi(argv[4]), atoi(argv[5]));
  if (!strcmp(argv[1], "attribute"))
    return _attribute(artifacts, out, atoi(argv[4]), atoi(argv[5]),
                      argc > 6 ? String.new(argv[6]) : "all");
  fprintf(stderr, "interop: no mode %s\n", argv[1]);
  return 2;
}
