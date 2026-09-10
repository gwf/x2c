/*  interop.x -- The diagnostic that explains the application results.

    One request is a chain of affine and activation steps on one tensor:
    `y = relu(y * a + b)`, repeated. Element counts of 1, 64, 4,096, and
    65,536 and 16, 128, or 512 operations per request separate the cost of
    reaching a kernel from the cost of the kernel.

    interop.cpp runs the identical ATen sequence with no wrapper at all, so
    the three programs bound host cost from both sides. It is a diagnostic,
    not another application framework.

      interop check   <artifacts> <out>
      interop time    <artifacts> <out> <chain|e<count>o<ops>> <requests>
      interop memory  <artifacts> <out> 4 <requests>
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

static int _check(String artifacts, String out) {
  Map values = _artifact(artifacts, "interop-init.pt");
  for (int e = 0; e < 4; e++) {
    for (int o = 0; o < 3; o++) {
      int count = interop_elements[e], operations = interop_operations[o];
      double result = _chain(_input(values, "x", count),
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
      for (int i = 0; i < 8; i++) (void) _chain(x, a, b, operations);
      double result = 0.0;
      double start = Bench.now();
      for (int i = 0; i < requests; i++) result += _chain(x, a, b, operations);
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
  Bench.begin(1024);
  Bench.record_text("language", "x2c");
  Bench.record_text("torch_version", Torch.version());
  Bench.record_int("cfg_artifact_version", ARTIFACT_VERSION);
  Bench.record_int("threads", Torch.num_threads());

  String artifacts = String.new(argv[2]), out = String.new(argv[3]);
  if (!strcmp(argv[1], "check")) return _check(artifacts, out);
  if (!strcmp(argv[1], "time"))
    return _time(artifacts, out, String.new(argv[4]), atoi(argv[5]));
  if (!strcmp(argv[1], "memory"))
    return _memory(artifacts, out, atoi(argv[4]), atoi(argv[5]));
  fprintf(stderr, "interop: no mode %s\n", argv[1]);
  return 2;
}
