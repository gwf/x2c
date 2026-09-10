# libtorch 2.10.0 profile

- Upstream release: PyTorch `2.10.0`, official CPU build for macOS arm64
- Archive:
  `https://download.pytorch.org/libtorch/cpu/libtorch-macos-arm64-2.10.0.zip`
- Archive SHA-256:
  `13061d97e561235d9e43c132f6dc9b08a60f487a833da53a951614a96d3e7d32`
- Prepared prefix: the archive's `include/` and `lib/` copied unchanged;
  no build step.
- Linked components: `libtorch`, `libtorch_cpu`, `libc10`, and the C++
  runtime, all dynamic, found by an rpath into the prepared prefix.
  `libomp` is loaded by `libtorch_cpu`.
- Used from the prefix: the ATen tensor library, `torch::nn` layers,
  `torch::optim` optimizers and its two schedules, `torch::data`'s MNIST
  IDX reader, and `torch::jit` for pickled checkpoints and TorchScript
  loading. All are headers and the dylibs above; no extra component is
  linked for them.
- License: BSD-3-Clause, reproduced in `LICENSES/PyTorch-2.10.0-BSD-3-Clause.txt`.
- Vendored source and local patches: none. `src/torch-shim.cpp` is this
  package's C ABI over the C++ API and is compiled against the prefix.
- Platform: macOS arm64 only in this milestone.

`dependency.json` is the machine-readable record. There is no stable C++
ABI, so the shim and any consumer are tied to exactly this version.
