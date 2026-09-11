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
python3 packages/torch/benchmarks/run.py env       --run-id session --optimizer stock
python3 packages/torch/benchmarks/run.py check     --run-id session
python3 packages/torch/benchmarks/run.py time      --run-id session \
    --samples 5 --threads 1,4
python3 packages/torch/benchmarks/run.py build --lane primary --counters
python3 packages/torch/benchmarks/run.py env --run-id diagnostics --optimizer stock
python3 packages/torch/benchmarks/run.py attribute --run-id diagnostics
python3 packages/torch/benchmarks/run.py memory    --run-id diagnostics \
    --profiles 1,2,3,4,5,6
for steps in 100000 200000 400000; do
  python3 packages/torch/benchmarks/run.py memory --run-id diagnostics \
    --profiles 1 --steps "$steps"
done
python3 packages/torch/benchmarks/run.py report --run-id session \
    --diagnostics-run diagnostics
python3 packages/torch/benchmarks/plots.py session diagnostics
```

That sequence is the whole session; `REPORT.md` and the plots come
out of the last two commands and read nothing but the JSON the earlier
ones wrote. `plots.py` needs matplotlib, which the pinned torch wheel's
interpreter does not have, so run it under an interpreter that does; it
never imports torch.

Run the required operation-order control separately:

```sh
python3 packages/torch/benchmarks/run.py env --run-id matched --optimizer matched
python3 packages/torch/benchmarks/run.py check --run-id matched
python3 packages/torch/benchmarks/run.py report --run-id matched
```

This writes `MATCHED.md`. The Python control uses libtorch 2.10's Adam
operation order; stock PyTorch remains the ordinary comparison in `REPORT.md`.
The control must satisfy the existing tolerances. Stock Adam's measured
floating-point divergence is reported separately, with any failed tolerance
kept visible and a nonzero `check` exit status. Never use control timings as
stock PyTorch timings. Each run-id fixes its optimizer selection and refuses
a conflicting selection later; output directories are separate. Check-mode
checkpoints are retained beside the raw logs. Preserve that evidence outside
a disposable worktree before deleting it.

`HISTORICAL-20260910.md` retains the earlier report and its evidence limits.

The timing counts are calibrated in `run.py` so the slower language takes
roughly 15 seconds per sample at one intra-op thread. `--updates`
overrides every lane at once, which is for checking the harness, not for
a reported session.

On macOS, x2c and the C++ control use `xb_now` in `membytes.c`, backed by
`clock_gettime(CLOCK_UPTIME_RAW)`. Python uses `time.perf_counter`, backed
by `mach_absolute_time` on this platform. Both clocks measure monotonic
elapsed time excluding system sleep; ordinary scheduling delays still count.
`CLOCK_MONOTONIC` includes system sleep on macOS and is unsuitable for this
comparison.

`prepare` needs the pinned wheel; `TORCH_PYTHON` names it and defaults to
`/Users/gary/Git/Bonsai-demo/.venv/bin/python`. The MNIST lane reads the
four published IDX files in place; `TORCH_MNIST` names the directory and
defaults to `/tmp/mnist-real`. `prepare` records their SHA-256 in
`config.json` beside the artifacts.

Datasets, binaries, and checkpoints live under
`unittest/build/torch-comparison/`; logs and raw samples under
`debug/torch-comparison/<run-id>/`.

### Checking the comparison runner

`check` requires each requested binary, every check-mode result, the emitted
x2c profile constants, and fresh first-update and final checkpoints from
both training programs. Interop checks its complete scalar result grid and
needs no checkpoints. A missing result is a failure, not a skipped check.

Checkpoint keys, shapes, and dtypes must match. Floating values use the
stated tolerance independently at each element; integer, boolean, and
`meta.*` values must match exactly. First-update values must pass. Final
floating weights may drift and are reported; final checkpoint structure,
finite values, task quality, and the existing loss tolerance still apply.

The optional runner regressions need the same torch interpreter but no
native compilation, downloaded data, or training:

```sh
"$TORCH_PYTHON" packages/torch/benchmarks/test-comparison.py
```

### The handle counters

`--counters` builds the package with `-DXT_HANDLE_COUNTERS`, which turns
on the private hooks `packages/torch/src/xt-handles.h` declares at the
hand-written wrapper, the generator's `xg_wrap` template, the returned
handle arrays, and every matching free. `handles.c` here supplies those
hooks and is the only thing that can read a count back: the package has
no inspection API for them, and an ordinary build expands both macros to
nothing and references no symbol.

The counters exist for memory and interop attribution, which need live
handles by kind rather than a single process footprint. They add two relaxed
atomic operations per handle. Headline timings use a counter-free build;
diagnostic measurements record their own build and environment. The report's
`--diagnostics-run` option and the plot command's second argument select that
separate evidence without relabeling instrumented timings.

### The two build lanes

`--lane primary` builds the x2c benchmark objects against the libtorch
dylibs inside the pinned Python wheel, so both languages call the same
backend binary and a timing difference is not a difference of
distributions. `--lane shipped` uses the package's own prepared prefix.

A lane reuses the package Makefile with the documented `TORCH_PREFIX`
override in `unittest/build/torch-comparison/lanes/`. Ordinary and counter
builds have separate directories. Each build refreshes private copies of the
authoritative sources; generated headers, archives, native objects, and link
inputs stay inside the private package. The package's ordinary `builds/`
directory is unchanged.
`bin/lane.json` records the selected configuration and library hashes.

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

`X2C_TORCH_THREADS` sets the intra-op thread count on both sides. Both
languages pin inter-op threads to 1 before any work.

Two diagnostics stand outside the modes above:

```sh
python3 packages/torch/benchmarks/firstdiff.py --variant explicit
$work/bin/interop attribute $work/artifacts $work/out 65536 60 subscope
```

`firstdiff.py` runs the paired `trace` mode over a range of updates and
reports the first update, and the first operation within it, where the
two implementations stop producing identical float32 values. `attribute`
runs the interop chain under one lifetime per process.

## The output records

Each program prints three kinds of line, and nothing else the runner
reads:

- `record <name> <number>` - one measured or configured number.
- `text <name> <value>` - the language, the torch version, the variant.
- `curve <update> <loss>` - one learning-curve point, printed in a check
  run only and never inside timed work.
- `sample <label> <index> <seconds> <footprint> <footprint_peak>
  <resident> <resident_peak> <live_allocations> <live_scopes>
  <allocation_calls> <free_calls> <requested_bytes> <pool_interned>
  <pool_active> <pool_backing> <pool_depot>` - one memory observation,
  followed by a final `dropped <count>`.

A counters build adds one `handles <label> <index>` line per sample
carrying live and peak counts for each of the seven handle kinds, a
`handlesum <kind> <created> <destroyed> <live> <peak>` line per kind at
the end, and `counters 1` so a run of zeros is never read as "no
handles".

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
| 2 | `tabular` | parameter enumeration, named parameters and top-k tuples over four batch shapes |
| 3 | `tabular` | a view and a clone surviving the scope that made them |
| 4 | `sequence`, `interop` | graph and scope granularity, gradient accumulation |
| 5 | `tabular` | 50 create-train-save-load-destroy cycles with injected errors |
| 6 | `tabular` | the positive control: deliberate retention, capped at 128 MiB |

Profile 6 exists to prove the measurement sees a known problem before any
other result is called healthy. It is not an example of ordinary use.

Profile 2's ordinary form runs the explicit parameter-enumeration forward,
materializes `named_parameters` and generated top-k results per request, and cycles
batch sizes 1, 8, 32 and 128. Both sides warm up 50 requests. The runner checks
output sums, exact index sums and enumeration counts before reporting memory.
`--churn-lifetime ordinary|pooled|hoisted` selects a fresh-process comparison.
The ordinary form enumerates per request. The pooled form wraps each x2c
request in a nested List pool; Python repeats its ordinary request. The hoisted
form on both sides retains named parameters and layer parameter handles once,
but still creates and consumes generated top-k results per request. x2c samples
Scope and canonical-pool statistics after request cleanup at the same root
pool depth. Variant names remain distinct in logs, merged results and reports;
rerunning another variant preserves the ordinary evidence.

```sh
for lifetime in ordinary pooled hoisted; do
  python3 packages/torch/benchmarks/run.py memory --run-id diagnostics \
      --profiles 2 --steps 100000 --churn-lifetime "$lifetime"
done
```

A nested pool bounds canonical retention in this workload. Hoisting reduces
it but does not eliminate new top-k List identities. Neither observation
implies a constant process footprint: native allocators retain separate caches.

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

## Supplemental diagnostics

The optional diagnostics fill in costs that whole-request timing cannot
attribute. They use separate run IDs and do not replace the primary timing
records. Counter-enabled phase timings are diagnostic observations only.

```sh
python3 packages/torch/benchmarks/run.py build --lane primary --counters
python3 packages/torch/benchmarks/run.py env --run-id supplement --optimizer matched
python3 packages/torch/benchmarks/run.py diagnose --run-id supplement \
    --optimizer matched --steps 512 --samples 3
python3 packages/torch/benchmarks/run.py memory --run-id supplement \
    --profiles 4 --steps 512
for requests in 1024 4096; do
  python3 packages/torch/benchmarks/run.py errors --run-id supplement \
      --steps "$requests"
done
for elements in 1 64 4096 65536; do
  python3 packages/torch/benchmarks/run.py attribute --run-id supplement \
      --elements "$elements" --requests 60
done
python3 packages/torch/benchmarks/run.py supplement --run-id supplement
python3 packages/torch/benchmarks/plots.py supplement --supplement
```

`diagnose` runs native and explicit tabular forwards, MNIST, and sequence
training. Each uses 50 warmup steps and fresh initial training state, then
reports batch preparation/zero-grad, forward/loss, backward, optimizer step,
and explicit cleanup separately. The startup measurement runs the same
application with `startup`, which exits after imports, native initialization
and thread configuration, before loading data. Loading, setup and model plus
optimizer checkpoint operations have their own timers. Compare load and
setup together: initial-weight loading belongs to different existing owners
in Python and x2c. These clocks perturb short operations. Python destruction
inside forward/backward remains in those columns; explicit cleanup is not
the total cost of lifetime management.

`errors` repeats the same native bad shape and catches it, then raises a
contextual request error with either fixed text or a unique request number.
Every request checks gradient-mode restoration and a valid forward result.
The samples distinguish native handles, Scope allocations, the shared canonical
String/List pool, and process footprint. Canonical message growth is not a
native tensor leak. Python does not have x2c's canonical pools.

The sequence memory sweep releases each model and optimizer before the next
window length. Its plot reports cumulative process high water through that
ascending sweep; earlier peaks and allocator caches are still present.
All interop sizes retain distinct logs and JSON, with Python and each x2c
lifetime checked against the direct C++ result.

[SUPPLEMENT.md](SUPPLEMENT.md) records the current supplemental results and
the unexplained remainder of the original canonical-churn process peak.
Stable native/Scope counts and bounded List storage do not identify the
source of that residual or establish general memory suitability.

The original MNIST timing warmed 20 batches. Its separate correction uses
50, with the same fresh model/optimizer reset and five pairs at each thread
count, in a counter-free build:

```sh
python3 packages/torch/benchmarks/run.py build --lane primary
python3 packages/torch/benchmarks/run.py env --run-id supplement-mnist50 --optimizer stock
caffeinate -is python3 packages/torch/benchmarks/run.py time \
    --run-id supplement-mnist50 --app mnist --threads 1,4 --samples 5
python3 packages/torch/benchmarks/run.py supplement --run-id supplement \
    --timing-run supplement-mnist50
```

The archived Python checks saved curves but did not print curve records.
To restore the plot from an existing check and its original retained files,
without modifying `check.json` or training again:

```sh
python3 packages/torch/benchmarks/plots.py original-run --paired-curves /path/to/original/out
```

This records file hashes and point counts in `paired-curves-provenance.json`.
The reconstructed tabular panel is paired; MNIST and sequence panels contain
Python only because the original native checks recorded no curves. Their
panel titles say so. Future Python checks emit their saved curve points too.
