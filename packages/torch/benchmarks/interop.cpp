/*  interop.cpp -- The C++ control for the interop diagnostic.

    The same ATen sequence with no wrapper, no scope, and no interpreter:
    `y = relu(y * a + b)` repeated, out of place, under inference mode.
    It bounds the host and wrapper cost the x2c and Python programs pay,
    which is all it is for. It is not another application framework and it
    does not read or write a checkpoint the applications depend on.

      interop-cpp check  <artifacts> <out>
      interop-cpp time   <artifacts> <out> <chain|e<n>o<k>> <requests>
*/

#include <torch/torch.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

extern "C" {
#include "membytes.h"
}

namespace {

const std::vector<int> kElements = {1, 64, 4096, 65536};
const std::vector<int> kOperations = {16, 128, 512};
const int kArtifactVersion = 1;

double now() {
  return xb_now();
}

void record(const std::string &name, double value) {
  std::printf("record %s %.12g\n", name.c_str(), value);
}

/* The artifacts are a pickled dict of name to tensor, the same file the
   other two programs read. torch::pickle_load returns it as an IValue. */
c10::Dict<c10::IValue, c10::IValue> load(const std::string &path) {
  std::vector<char> data;
  std::FILE *handle = std::fopen(path.c_str(), "rb");
  if (!handle) {
    std::fprintf(stderr, "interop-cpp: cannot open %s\n", path.c_str());
    std::exit(2);
  }
  std::fseek(handle, 0, SEEK_END);
  data.resize(static_cast<size_t>(std::ftell(handle)));
  std::fseek(handle, 0, SEEK_SET);
  if (std::fread(data.data(), 1, data.size(), handle) != data.size()) {
    std::fprintf(stderr, "interop-cpp: short read on %s\n", path.c_str());
    std::exit(2);
  }
  std::fclose(handle);
  return torch::pickle_load(data).toGenericDict();
}

at::Tensor field(const c10::Dict<c10::IValue, c10::IValue> &values,
                 const std::string &name) {
  auto found = values.find(name);
  if (found == values.end()) {
    std::fprintf(stderr, "interop-cpp: no %s in the artifact\n", name.c_str());
    std::exit(2);
  }
  return found->value().toTensor();
}

double chain(const at::Tensor &x, const at::Tensor &a, const at::Tensor &b,
             int operations) {
  c10::InferenceMode guard;
  at::Tensor y = x;
  for (int i = 0; i < operations; i++) y = at::relu(y * a + b);
  return y.sum().item<double>();
}

}  // namespace

int main(int argc, char **argv) {
  if (argc < 4) {
    std::fprintf(stderr, "usage: interop-cpp <check|time> <artifacts> <out>"
                         " [variant] [requests]\n");
    return 2;
  }
  const char *threads = std::getenv("X2C_TORCH_THREADS");
  at::set_num_threads(threads ? std::atoi(threads) : 1);
  at::set_num_interop_threads(1);
  std::printf("text language cpp\n");
  std::printf("text torch_version %s\n", TORCH_VERSION);
  std::printf("record threads %d\n", at::get_num_threads());
  std::printf("record footprint %llu\n",
              static_cast<unsigned long long>(xb_footprint()));

  const std::string artifacts = argv[2];
  auto values = load(artifacts + "/interop-init.pt");
  if (field(values, "meta.version").item<int64_t>() != kArtifactVersion) {
    std::fprintf(stderr, "interop-cpp: artifact version mismatch\n");
    return 2;
  }

  if (!std::strcmp(argv[1], "check")) {
    for (int count : kElements)
      for (int operations : kOperations)
        record("chain_e" + std::to_string(count) + "_o" +
                   std::to_string(operations),
               chain(field(values, "x." + std::to_string(count)),
                     field(values, "a." + std::to_string(count)),
                     field(values, "b." + std::to_string(count)), operations));
    return 0;
  }

  if (std::strcmp(argv[1], "time")) {
    std::fprintf(stderr, "interop-cpp: no mode %s\n", argv[1]);
    return 2;
  }

  const std::string variant = argv[4];
  const int requests = std::atoi(argv[5]);
  int only_elements = 0, only_operations = 0;
  if (variant != "chain") {
    const size_t split = variant.find('o', 1);
    only_elements = std::atoi(variant.substr(1, split - 1).c_str());
    only_operations = std::atoi(variant.substr(split + 1).c_str());
  }
  std::printf("text variant %s\n", variant.c_str());

  double total = 0.0;
  for (int count : kElements) {
    for (int operations : kOperations) {
      if (only_elements &&
          (count != only_elements || operations != only_operations))
        continue;
      auto x = field(values, "x." + std::to_string(count));
      auto a = field(values, "a." + std::to_string(count));
      auto b = field(values, "b." + std::to_string(count));
      for (int i = 0; i < 8; i++) chain(x, a, b, operations);
      double result = 0.0;
      const double start = now();
      for (int i = 0; i < requests; i++) result += chain(x, a, b, operations);
      const double seconds = now() - start;
      total += seconds;
      const std::string suffix =
          "e" + std::to_string(count) + "_o" + std::to_string(operations);
      record("seconds_" + suffix, seconds);
      record("ns_per_op_" + suffix,
             seconds * 1e9 / (static_cast<double>(requests) * operations));
      record("result_" + suffix, result);
    }
  }
  record("requests", requests);
  record("steady_seconds", total);
  return 0;
}
