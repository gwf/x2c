# Matched x2c and PyTorch applications

Four paired workloads, the same work on both sides, run live. Each pair
reads one set of artifacts, prints the same records, and is compared by a
runner that owns no model logic. The plan is
[plans/x2c-torch-comparison.md](../../../plans/x2c-torch-comparison.md).

This suite is optional. It is outside `test`, `check`, `packages-check`,
`precommit`, and every publication gate, and it adds nothing to them.

| Lane | x2c | Python | What it answers |
| --- | --- | --- | --- |
| 1 tabular regression and batched prediction | `tabular.x` | `tabular.py` | training and request cost on a dense MLP |
| 2 MNIST convolutional classification | `mnist.x` | `mnist.py` | the kernel-heavy case, native modules on both sides |
| 3 stateful sequence forecasting | `sequence.x` | `sequence.py` | truncated backpropagation and surviving state |
| interop diagnostic | `interop.x` | `interop.py`, `interop.cpp` | what the application results are made of |

`interop.cpp` is a control, not an application: it runs the identical ATen
sequence with no wrapper, so host cost is bounded from both sides.

## Running it

```sh
python3 packages/torch/benchmarks/run.py prepare
python3 packages/torch/benchmarks/run.py build --lane primary
python3 packages/torch/benchmarks/run.py check
python3 packages/torch/benchmarks/run.py time --samples 5 --threads 1,4
python3 packages/torch/benchmarks/run.py memory --profiles 1,3,4,5,6
python3 packages/torch/benchmarks/run.py env
```

`prepare` needs the pinned wheel; `TORCH_PYTHON` names it and defaults to
`/Users/gary/Git/Bonsai-demo/.venv/bin/python`. The MNIST lane reads the
four published IDX files in place; `TORCH_MNIST` names the directory and
defaults to `/tmp/mnist-real`. `prepare` records their SHA-256 in
`config.json` beside the artifacts.

Datasets, binaries, and checkpoints live under
`unittest/build/torch-comparison/`; logs and raw samples under
`debug/torch-comparison/<run-id>/`.

### The two build lanes

`--lane primary` builds the x2c benchmark objects against the libtorch
dylibs inside the pinned Python wheel, so both languages call the same
backend binary and a timing difference is not a difference of
distributions. `--lane shipped` uses the package's own prepared prefix.

A lane build re-points the package's own `builds/torch-shim.o`,
`builds/xt_ops.o`, and `builds/torch.link` through the documented
`TORCH_PREFIX` override, and records the prefix in
`builds/benchmark-lane`. Run `run.py build --lane shipped` to put the
package back on its prepared prefix.

### Running one application directly

Every program stands alone. The runner passes exactly these arguments:

```sh
work=unittest/build/torch-comparison
$work/bin/tabular check $work/artifacts $work/out
$work/bin/tabular time  $work/artifacts $work/out native 20000
$work/bin/tabular memory $work/artifacts $work/out 1 512
$work/bin/mnist    time  $work/artifacts $work/out epoch 300
$work/bin/sequence memory $work/artifacts $work/out 4 64
$work/bin/interop  time  $work/artifacts $work/out chain 100
python3 packages/torch/benchmarks/tabular.py check $work/artifacts $work/out
```

`X2C_TORCH_THREADS` sets the intra-op thread count on both sides.

## The output records

Each program prints three kinds of line, and nothing else the runner
reads:

- `record <name> <number>` - one measured or configured number.
- `text <name> <value>` - the language, the torch version, the variant.
- `sample <label> <index> <seconds> <footprint> <footprint_peak>
  <resident> <resident_peak> <live_allocations> <live_scopes>
  <allocation_calls> <free_calls> <requested_bytes> <pool_interned>
  <pool_active> <pool_backing> <pool_depot>` - one memory observation,
  followed by a final `dropped <count>`.

The Scope and pool columns are zero from Python: that layer does not
exist there, and zero never means "empty". Samples land in an array
`Bench.begin` reserves once, so measurement does not allocate inside the
work it measures; `dropped` is non-zero when a series outran that
reservation, which invalidates its tail.

`membytes.c` is the process sampler. x2c links it as an ordinary C input
and Python loads the same source built as a dylib through ctypes, so both
read `phys_footprint`, the ledger peak, and resident size from the same
`task_info` call.

## Memory profiles

| # | Where | What it holds |
| --- | --- | --- |
| 1 | `tabular` | steady training then inference at a fixed shape |
| 3 | `tabular` | a view and a clone surviving the scope that made them |
| 4 | `sequence`, `interop` | graph and scope granularity, gradient accumulation |
| 5 | `tabular` | 50 create-train-save-load-destroy cycles with injected errors |
| 6 | `tabular` | the positive control: deliberate retention, capped at 128 MiB |

Profile 6 exists to prove the measurement sees a known problem before any
other result is called healthy. It is not an example of ordinary use.

## Matching

`prepare.py` writes the data, the exact initial parameters and buffers,
and the batch indices; both languages load them. Equal seeds are not
equal initial conditions across two libraries. Every artifact carries
`meta.version`, and a program refuses a mismatch rather than comparing
different work.

Acceptance, in the order it is checked:

1. One update with every value kept: outputs, loss, every gradient, every
   parameter and buffer afterwards, at `atol=1e-6, rtol=1e-4`.
2. Save, reload, and resume against uninterrupted training, optimizer
   state included. The optimizer archive is for x2c and C++ only.
3. Task quality against the untrained model and the stated baselines,
   with the final losses agreeing to `1e-3` relative.

Long-run per-weight equality is reported, not required: float32 training
diverges from a one-ulp difference over thousands of updates.

`PILOT.md` holds the first measurements and the gaps they exposed.
