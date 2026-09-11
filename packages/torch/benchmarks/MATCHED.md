# x2c and PyTorch applications: results

Three applications and one diagnostic, the same work on both sides, run
live in fresh processes on one machine. [README.md](README.md) gives the
method, plan, and reproduction commands;
[PILOT.md](PILOT.md) holds the earlier single-sample pass and the gaps it
found.

Read the correctness results alongside the timings: a measured timing is
not evidence that a configuration passed. There is no aggregate speedup in
this report; the workloads and their verdicts are separate.

Optimizer comparison: **matched**.

Python uses an operation-order control for libtorch Adam. This session records correctness only.

## What ran

- Tree `2b7a63cbb2270eaf1ceba98b31b089fcae56850f` plus uncommitted changes, `x2c 0.12.0`.
- macOS-15.7.9-arm64-arm-64bit-Mach-O, Apple M4 Max, 16 physical and 16 logical cores.
- Build lane `primary`, prefix `/Users/gary/Git/Bonsai-demo/.venv/lib/python3.11/site-packages/torch`, handle counters off.
  - `libtorch_cpu.dylib` 214082912 bytes, SHA-256 `941f3e16a8e02b23`
  - `libtorch.dylib` 16736 bytes, SHA-256 `2178657b7eeffc0c`
  - `libc10.dylib` 1084640 bytes, SHA-256 `f203c171b7a71c74`
- Python at `/Users/gary/Git/Bonsai-demo/.venv/bin/python`, torch `2.10.0`.
- Artifacts, SHA-256 prefixes: `interop-init.pt 7d2ca9e5c1bc`, `mnist-batches.pt d13f17c6f88a`, `mnist-init.pt 8f855dfc9ea5`, `sequence-data.pt 72665ed75b42`, `sequence-init.pt 939cffb5ef4a`, `tabular-batches.pt ebaf4a532b32`, `tabular-data.pt a9465db47665`, `tabular-init.pt bf60a5298a61`.

## Correctness

One update with every value kept is the decisive check: outputs, loss, every gradient, every parameter and buffer afterwards, against `atol=1e-6, rtol=1e-4`.

| Lane | Tensors compared after one update | Worst absolute | Verdict |
| --- | --- | --- | --- |
| mnist | 32 | 0.000e+00 | bit-identical |
| sequence | 12 | 0.000e+00 | bit-identical |
| tabular | 14 | 0.000e+00 | bit-identical |


Task quality and the plan's `1e-3` relative loss tolerance:

| Lane | Measure | x2c | Python | Relative | Verdict |
| --- | --- | --- | --- | --- | --- |
| interop | chain_e1_o128 | 0.83724821 | 0.83724821 | 0.00e+00 | ok |
| interop | chain_e1_o16 | 0.79481524 | 0.79481524 | 0.00e+00 | ok |
| interop | chain_e1_o512 | 0.88197315 | 0.88197315 | 0.00e+00 | ok |
| interop | chain_e4096_o128 | 2113.1189 | 2113.1189 | 0.00e+00 | ok |
| interop | chain_e4096_o16 | 1618.4708 | 1618.4708 | 0.00e+00 | ok |
| interop | chain_e4096_o512 | 3626.7097 | 3626.7097 | 0.00e+00 | ok |
| interop | chain_e64_o128 | 39.357796 | 39.357796 | 0.00e+00 | ok |
| interop | chain_e64_o16 | 28.929104 | 28.929104 | 0.00e+00 | ok |
| interop | chain_e64_o512 | 63.224529 | 63.224529 | 0.00e+00 | ok |
| interop | chain_e65536_o128 | 34553.102 | 34553.102 | 0.00e+00 | ok |
| interop | chain_e65536_o16 | 26398.844 | 26398.844 | 0.00e+00 | ok |
| interop | chain_e65536_o512 | 60244.285 | 60244.285 | 0.00e+00 | ok |
| interop | interop_threads | 1 | 1 | 0.00e+00 | ok |
| mnist | data_checksum | -6262.4365 | -6262.4365 | 0.00e+00 | ok |
| mnist | interop_threads | 1 | 1 | 0.00e+00 | ok |
| mnist | mode_after_reload | 1 | 1 | 0.00e+00 | ok |
| mnist | probe_loss | 2.3025608 | 2.3025608 | 0.00e+00 | ok |
| mnist | reloaded_accuracy | 0.9865 | 0.9865 | 0.00e+00 | ok |
| mnist | test_checksum | -21465.027 | -21465.027 | 0.00e+00 | ok |
| mnist | trained_accuracy | 0.9865 | 0.9865 | 0.00e+00 | ok |
| mnist | untrained_accuracy | 0.0874 | 0.0874 | 0.00e+00 | ok |
| sequence | interop_threads | 1 | 1 | 0.00e+00 | ok |
| sequence | last_value_val_mse | 0.0021322735 | 0.0021322735 | 0.00e+00 | ok |
| sequence | mean_val_mse | 0.29780677 | 0.29780677 | 0.00e+00 | ok |
| sequence | probe_loss | 0.27235726 | 0.27235726 | 0.00e+00 | ok |
| sequence | resumed_val_mse | 0.052497877 | 0.052497877 | 0.00e+00 | ok |
| sequence | trained_val_mse | 0.052508756 | 0.052508756 | 0.00e+00 | ok |
| sequence | untrained_val_mse | 0.32913961 | 0.32913961 | 0.00e+00 | ok |
| sequence | window128_val_mse | 0.1410817 | 0.1410817 | 0.00e+00 | ok |
| sequence | window32_val_mse | 0.14179125 | 0.14179125 | 0.00e+00 | ok |
| sequence | window8_val_mse | 0.14052584 | 0.14052584 | 0.00e+00 | ok |
| tabular | explicit_val_mse | 0.032052495 | 0.032052495 | 0.00e+00 | ok |
| tabular | interop_threads | 1 | 1 | 0.00e+00 | ok |
| tabular | mean_val_mse | 0.33111256 | 0.33111256 | 0.00e+00 | ok |
| tabular | predict1_checksum | 948.31848 | 948.31848 | 0.00e+00 | ok |
| tabular | predict256_checksum | 239999.31 | 239999.31 | 0.00e+00 | ok |
| tabular | predict32_checksum | 29976.425 | 29976.425 | 0.00e+00 | ok |
| tabular | probe_loss | 0.38660234 | 0.38660234 | 0.00e+00 | ok |
| tabular | resumed_val_mse | 0.032104194 | 0.032104194 | 0.00e+00 | ok |
| tabular | trained_val_mse | 0.032104194 | 0.032104194 | 0.00e+00 | ok |
| tabular | untrained_val_mse | 0.36317796 | 0.36317796 | 0.00e+00 | ok |

Per-weight equality after the full profile is reported, not required; float32 training separates from a one-ulp difference. Worst absolute difference at the end: `mnist` 0.00e+00, `sequence` 0.00e+00, `tabular` 0.00e+00.

## Historical context

[The earlier report](HISTORICAL-20260910.md) retains its measurements, failures and analysis. Those observations are not results from this session.

## Raw data

Correctness and timing records come from `debug/torch-comparison/closeout-final-matched/`: `check.json` and `environment.json`, beside one log per launched process and the complete checkpoints.
