# libtorch 2.10.0 profile

- Upstream release: PyTorch `2.10.0`, official macOS arm64 and Linux x86_64
  CPU distributions. The macOS distribution also supplies MPS.
- Archive:
  `https://download.pytorch.org/libtorch/cpu/libtorch-macos-arm64-2.10.0.zip`
- Archive SHA-256:
  `13061d97e561235d9e43c132f6dc9b08a60f487a833da53a951614a96d3e7d32`
- Linux archive:
  `https://download.pytorch.org/libtorch/cpu/libtorch-shared-with-deps-2.10.0%2Bcpu.zip`
- Linux archive SHA-256:
  `c5bf8efda9224a2d971b19d1ef6cf3ba6fee8ab53e69c49427db003d1d300496`
- Prepared prefix: the archive's `include/` and `lib/` copied unchanged;
  no build step.
- Linked components: `libtorch`, `libtorch_cpu`, `libc10`, and the C++
  runtime, all dynamic, found by an rpath into the prepared prefix.
  macOS uses libc++ and `libomp`; Linux uses libstdc++ and `libgomp`.
- Used from the prefix: the ATen tensor library, `torch::nn` layers,
  `torch::optim` optimizers and its two schedules, `torch::data`'s MNIST
  IDX reader, and `torch::jit` for pickled checkpoints and TorchScript
  loading. All are headers and the dylibs above; no extra component is
  linked for them.
- License: BSD-3-Clause, reproduced in `LICENSES/PyTorch-2.10.0-BSD-3-Clause.txt`.
- Vendored source and local patches: none. `src/torch-shim.cpp` is this
  package's C ABI over the C++ API and is compiled against the prefix.
- Platforms: macOS arm64 CPU/MPS and Linux x86_64 CPU with the C++11 ABI.
  The Linux correctness lane uses Ubuntu 24.04 and Clang 18 under local
  Docker x86_64 emulation; it does not establish native Linux performance.

`dependency.json` and `dependency-linux.json` are the machine-readable
records, selected by the host platform. There is no stable C++ ABI, so the
shim and any consumer are tied to exactly this version.
