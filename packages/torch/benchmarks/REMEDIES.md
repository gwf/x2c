# Tensor-chain lifetime comparison

The same affine-and-activation tensor chain runs through x2c and the original PyTorch implementation. Explicit release frees the replaced named tensor; a scope per iteration carries only the running value onward. The original request scope remains a separate lifetime control.

## What ran

- Measured 2026-09-11T11:57:08.763751-07:00 through 2026-09-11T12:02:45.388254-07:00.
- Apple M4 Max, macOS 15.7.9 arm64; PyTorch 2.10.0 and the same native backend libraries.
- Compiler source `3dc079e19838bcf8c8c1b8399d948189683d0aa4`; lane `primary`, handle counters off.
- Fresh measurements of the preserved evidence-only harness and package built from 3dc079e19838bcf8c8c1b8399d948189683d0aa4. The harness selects existing loop implementations and removes live-footprint sampling from the timed bodies. These samples predate the committed benchmark runner integration.
- Fresh processes ran serially, with alternating language order and rotating variant order. Task-owned builds finished before timing. Command-scoped sleep prevention was active. Unrelated desktop applications remained running; the host was not isolated.

## Full-grid runtime

5 fresh-process pairs per configuration, with language order alternating. Median seconds and paired Python medians are shown below; lower is faster. Spread is (maximum - minimum) / median, not a confidence interval.

| Threads | x2c lifetime | x2c (s) | Spread | Python (s) | Spread | x2c/Python |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Explicit release | 2.5983 | 4.5% | 2.6475 | 2.3% | 0.981x |
| 1 | Scope per iteration | 2.6955 | 2.6% | 2.6710 | 1.1% | 1.009x |
| 1 | Original request scope (control) | 7.0624 | 6.7% | 2.6466 | 0.9% | 2.669x |
| 4 | Explicit release | 5.9687 | 2.6% | 6.1884 | 2.8% | 0.964x |
| 4 | Scope per iteration | 6.0970 | 9.1% | 6.2396 | 4.4% | 0.977x |
| 4 | Original request scope (control) | 8.3970 | 4.2% | 6.2614 | 2.0% | 1.341x |

Small median differences on an active desktop do not establish a general ranking. Each Python value is the median of the processes paired directly with that x2c lifetime. The original loop and both remedies receive the same inputs and perform the same tensor operations. These are complete request timings with counter and footprint sampling disabled, rather than instrumented phase costs.

## Correctness and work

All 72 check-mode scalar comparisons and all 360 accumulated timing-result comparisons agree with Python with zero tolerance. The report rechecks the preserved process values before rendering. Both programs report 12 significant digits: this is exact equality of reported scalar results, not bitwise equality of every tensor element.

The grid uses element counts 1, 64, 4096, 65536 and chain lengths 16, 128, 512. Each cell has 8 warmup requests and 190 measured requests (2,280 per full sweep). Loading and warmup are outside the reported runtime; the timed cells are summed. Inter-op threads remain at 1.

Excluded samples: none; every launched timing pair is retained.

## Scope of the result

These measurements compare lifetime choices for this CPU chain. They do not resolve the separate canonical-pool churn footprint excess or establish general memory suitability. Native C++ remains a separate diagnostic control in the [original report](REPORT.md), not the Python comparison here. The original application results and [MNIST correction](SUPPLEMENT.md) are separate measurements.

## Evidence and reproduction

- [Every timing pair](results/chains-20260911/timing.json), including order.
- [Correctness comparisons](results/chains-20260911/correctness.json).
- [Per-process scalar records](results/chains-20260911/records.json).
- [Provenance and hashes](results/chains-20260911/provenance.json).
- torch-chain-remedies-20260911: original source, generated C, build command, executable, logs, process snapshots, and full provenance are retained separately.

Regenerate this report from the saved observations without running benchmarks:

```sh
python3 packages/torch/benchmarks/run.py remedies-report --results packages/torch/benchmarks/results/chains-20260911
```

The [benchmark README](README.md) describes how to collect a new run. Regeneration writes only `REMEDIES.md`; it preserves the original reports.
