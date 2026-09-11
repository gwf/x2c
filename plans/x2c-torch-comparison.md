# Matched x2c and PyTorch applications: correctness, memory, and performance

> Status: active
> The suite, applications, and report shipped in 9c36b76, with temporary
> cleanup measurements in dbba113. Acceptance-check repairs followed on
> 2026-09-10. Historical raw checkpoints were not retained in the linked
> worktrees, so the repaired checks cannot revalidate those results here.
> Primary and supplemental acceptance are recorded; final publication
> and deployment remain.
> The matched Adam control passes. Stock Adam's recorded explicit tabular
> loss divergence remains a failed tolerance and the accepted limitation.

## Fresh acceptance, 2026-09-11

Retirement review found missing phase/startup costs, unique-message error
churn, all four C++ attribution sizes, and a sequence-window lifetime
correction/plot. The separate supplemental session now records those cases:
12 paired phase blocks, nine startup pairs, fixed/unique errors at 1,024
and 4,096 requests, all four interop sizes, and corrected sequence sweeps.
The sequence model/optimizer handles return to zero between windows.
The primary measurements below retain their original source and outcomes.
Their MNIST timing used 20 warmup batches. The separate counter-free
correction uses the required 50 and records five fresh-process pairs at
one and four threads. All 20 processes completed: median x2c/Python times
are 14.1525/14.3631 seconds and 9.9758/10.2849 seconds respectively.
The original results remain explicitly labeled. Supplemental evidence is
under `torch-comparison/supplement` beside the primary evidence below.
The residual process-footprint excess in pooled canonical churn remains
unresolved; stable owner counts do not establish its allocator cause or
general memory suitability. This is a measured limitation, not a hidden
passing verdict or authorization for another runtime redesign.

The final primary session uses the pinned 2.10.0 wheel, counter-free native
objects, 16 timing configurations with five fresh-process pairs each, full
first-update and final checkpoints, and separate matched/stock verdicts.
All 160 timing process logs are retained. Command-scoped sleep prevention
was active; no host sleep was recorded. The host was not isolated from
unrelated desktop applications or Docker services.

A separate counter-enabled session covers 17 paired memory profiles,
including steady use and ordinary/pooled/hoisted canonical churn at
100,000, 200,000 and 400,000 requests. Every sample log reports zero dropped
records and every process remains below the 2 GiB cap. Native handle and
Scope counts are stable after request cleanup; ordinary canonical storage
grows, while per-request List pool brackets keep it fixed. Attribution
also measures the cost of scope length and explicit early release.

[REPORT.md](../packages/torch/benchmarks/REPORT.md) retains stock failures,
per-workload timing variability, incremental memory peaks and attribution.
[MATCHED.md](../packages/torch/benchmarks/MATCHED.md) records the separate
passing control. No threshold was relaxed: stock explicit tabular loss has
0.223% relative divergence against the 0.1% limit. Counter-enabled and
sleep-affected prior timings remain historical, not headline measurements.

Raw commands, environments, checkpoints, binaries, source archive and logs
are preserved at
`/Users/gary/Documents/x2c-evidence/closeout-20260910/torch-comparison/`.
The `final-session` directory owns the final primary evidence.
The separate `shipped-final` directory records the packaged-library lane:
counter-free build, matched Adam, all four applications passing 41 agreement
rows, complete checkpoints and binaries. It is correctness evidence only;
headline timing uses the primary wheel lane above.

## Outcome and boundary

Build and run the same three useful CPU applications in ordinary x2c and
Python PyTorch. Establish whether they learn and produce equivalent results,
whether long-running use has bounded memory, and where interop and lifetime
management help or hurt performance. Add one small diagnostic workload to
explain the application results. Deliver sources, reproducible commands,
raw measurements, plots, and a candid comparison report.

This is an optional experiment suite, outside `test`, `check`,
`packages-check`, `precommit`, and publication gates. No speedup threshold,
recurring gate, new framework, GPU support, or toolchain installation is
part of the work. Run both languages live; the historical pure-Python
shootout baselines do not answer this question. Do not assume that x2c's
advantages on Python loops extend to loops dominated by native kernels.

The first supported comparison is macOS arm64 CPU and torch 2.10.0. MLP,
sequence, and interop work can start on M1/M2. The CNN uses the ongoing M3
module/MNIST work when available; do not silently replace it with another
tiny MLP or build a second module adapter to bypass that dependency.

## Existing owners and evidence

- `packages/torch/examples/mlp.x` owns the current composition/training
  idiom, including parameter enumeration inside forward. Preserve that
  straightforward usage as a baseline before trying faster alternatives.
- `tests/checkpoint-roundtrip.x` and `tests/verify-python.py` demonstrate
  shared initialization/data through checkpoints. Their current 20-step,
  64-row comparison of scalar losses is useful but not this experiment.
- `schema/README.md` records actual generated coverage. Use existing
  operations, `Module`, `Optimizer`, and checkpoints rather than new ML
  implementations. `Module.forward` can invoke native Linear directly.
- `lib/scope.x`: release destroys scoped allocations and their finalizers;
  `Scope.stats().requested_bytes` is cumulative, not live memory. Lists
  and Strings survive scope release. `Tensor.free()` drops the native
  handle but leaves the wrapper until its owning scope closes.
- `lib/pool.x` and `lib/list.x`: `Pool.stats(List.pool_current())` reports
  canonical-pool activity/storage. Pool promotion does not move the scoped
  Tensor wrappers a List contains. `Scope.move` moves one allocation.
- `examples/shootout/README.md` supplies the same-work comparison principle;
  `unittest/benchmarks/` supplies optional fresh-process timing precedents.
  Reuse their ideas, not their saved baselines or acceptance thresholds.

## Applications and fixed reference profiles

Each application has a correctness run, a repeated performance run, and a
memory run. Both languages receive identical configuration and artifacts.
Inputs and models fit comfortably in a normal development machine; the
initial target is under 1 GiB per process. Set an external 2 GiB footprint
stop limit and a 10-minute per-process timeout; a stopped case is incomplete,
never a passing result. Adjust a common profile only after a documented
pilot, before collecting either language's final samples.

### 1. Tabular nonlinear regression and batched prediction

- Generate 32,768 training and 8,192 held-out rows, 128 float32 features,
  and 8 regression targets once in Python. A frozen seeded two-layer
  nonlinear teacher plus fixed small noise supplies targets. Record the
  teacher/data hashes. This is controlled synthetic regression, not a
  claim about performance on a public real-world dataset.
- Train a 128-256-128-8 ReLU MLP, Adam at 1e-3, batch 128, for 1,024
  updates. Use precomputed batch indices, not per-language RNG streams.
  Save predictions, validation MSE, parameters, and optimizer-resume data.
- Compare held-out MSE with the untrained model and a constant-mean
  predictor. Both trained programs must beat both baselines. Establish
  any stronger learning threshold from the Python pilot before x2c tuning.
- Exercise native Linear forward in the primary application on both sides.
  Also measure the current documented explicit `x @ weight.t() + bias`
  forward on both sides, including its parameter enumeration. Label this
  separately: it changes calls and lifetime pressure, not the model.
- Prediction serves batches of 1, 32, and 256 with inference mode and one
  request scope. It exposes latency and cleanup costs hidden by training.

### 2. MNIST convolutional classification

- Reuse M3's MNIST preparation and pinned source checksums. Use all 60,000
  training and 10,000 test images, normalized once with fixed constants.
  Preload data for compute timing; report preparation separately.
- Architecture: Conv2d(1,16,3,padding=1), BatchNorm, ReLU, max-pool(2),
  Conv2d(16,32,3,padding=1), BatchNorm, ReLU, max-pool(2), flatten,
  Linear(1568,128), ReLU, Linear(128,10). No dropout in the matched lane,
  avoiding unequal RNG masks. Use native modules on both sides.
- Cross-entropy, Adam at 1e-3, batch 64, two full epochs; retain the final
  partial batch on both sides. Precompute identical epoch permutations.
  Initial acceptance target: at least 95% held-out accuracy in each
  implementation and at most 0.5 percentage-point difference.
- Compare BatchNorm buffers and train/eval behavior, not just weights.
  Verify reload reproduces predictions. This is the kernel-heavy case:
  report images/second and peak activation memory as well as total time.

### 3. Stateful sequence forecasting with truncated backpropagation

- Generate fixed train/held-out streams from a seeded driven nonlinear
  dynamical system: 8 observed channels from 16 latent channels, using a
  fixed recurrent matrix scaled to spectral norm 0.8, four sinusoidal
  drivers, a tanh state update, and small fixed observation noise. Vary
  driver frequencies/phases across streams; hold out phases for evaluation.
  The forcing keeps the task from decaying to a constant. Store data;
  no regeneration inside timed work.
  Use 32 parallel training streams of 4,096 steps and disjoint held-out
  streams of 1,024 steps. Predict the next observation.
- A simple tanh recurrent model has input width 8, hidden width 64, and
  output width 8. Compose two affine terms for the recurrent update and
  one output projection using current Linear/tensor operations in BOTH
  languages; Python must not substitute a fused native RNN for this lane.
- Train 512 windows of length 32, batch 32, Adam at 1e-3. Carry the hidden
  state across adjacent windows and detach it at each truncation boundary;
  reset at stream boundaries. Preserve only that state across x2c scopes.
- Score held-out MSE against untrained, constant-mean, and last-value
  predictors. Require improvement over untrained and mean predictions;
  report the last-value comparison even if it wins. Tune a common learning
  profile in the Python pilot if the task is not meaningfully learned.
- Sweep window lengths 8, 32, and 128 for peak-memory/call-cost diagnosis.
  This deliberately retains a useful graph within each window and releases
  it between windows. Correctly surviving detached state is essential.

## Matching and numerical acceptance

1. Python prepares versioned artifacts: data, batch indices, exact initial
   parameters/buffers, and configuration. Reuse the existing plain-dict
   checkpoint crossing, its documented allowlist, and checksums. Equal
   seeds alone are not evidence of equal initial conditions.
2. Pin dtype, loss reduction, layout, optimizer options, epsilon, weight
   decay, bias settings, zero-grad behavior, mode, and update order. Match
   Python Adam to the C++ algorithm (`foreach=False`, `fused=False` where
   supported); do not compare different optimizer implementations silently.
   Measured 2026-09-10: those flags are not sufficient. Python's Adam
   updates the first moment with `exp_avg.lerp_(grad, 1 - beta1)` while
   libtorch's C++ Adam uses `exp_avg.mul_(beta1).add_(grad, 1 - beta1)`;
   the two agree only while the moment is zero, so update 0 is bit-exact
   and update 1 differs by one ulp. Bit-exact long runs need a Python
   replay of the C++ form; otherwise expect ulp-level drift and judge by
   the loss tolerance.
3. Before long runs, compare full forward outputs, loss, parameter
   gradients, and parameters after one update. Float32 starting tolerance:
   `atol=1e-6, rtol=1e-4`; reject non-finite values. Integer metadata and
   labels agree exactly. Report maximum absolute and normalized errors.
4. Compare saved milestones and final evaluation. Long-run acceptance is
   task quality plus prediction/loss agreement, not bit equality of every
   weight after thousands of updates. Starting relative loss tolerance is
   1e-3; any relaxation needs an isolated numerical explanation and must
   be recorded, not chosen to make a failed run pass.
5. Check uninterrupted versus save/reload/resume within each language,
   including optimizer state. Check module checkpoints across languages.
   Do not claim Python interoperability of the C++ optimizer archive.
6. Every timed configuration first passes its correctness counterpart.
   A missing wrapper, required raw call, or awkward workaround is recorded
   as a portability gap, not hidden in a timing harness.

## Performance methodology

- Run optimized x2c and ordinary eager Python PyTorch in separate fresh
  processes, serially, on the same idle machine. Coordinate a quiet window
  around other agents' builds; contention makes samples inconclusive.
- Primary attribution lane: build isolated x2c benchmark objects against
  the exact libtorch dylibs used by the pinned Python wheel through the
  existing prefix override. Record loaded library paths/hashes and build
  configuration. Separately confirm the shipped zip-backed x2c build's
  correctness. If identical backend binaries are unavailable, label that
  comparison as different distributions, not language-only overhead.
- Use intra-op thread counts 1 and 4 (or available cores if fewer), with
  inter-op threads fixed to 1 before work where exposed. Record actual
  settings, BLAS/OpenMP configuration, CPU, OS, Python/torch versions,
  compiler flags, source tree/hash, and environment. A missing control is
  a documented limitation; do not change the host toolchain to obtain it.
- Warm lazy kernels and Adam state for 50 representative steps, then
  restore the same initial model/optimizer state before measured training
  on both sides. Warmup
  must not change the training problem. Keep initialization/import, data
  loading, checkpoint I/O, and steady compute as separate measurements.
- Collect five fresh-process pairs per main configuration, alternating
  x2c/Python order. Use monotonic clocks; time whole step/request blocks,
  including required cleanup. No per-op logging or timers in the hot loop.
  Report medians, spread, all raw samples, and paired Python/x2c ratios.
- For training, time a common fixed update window after warmup, calibrated
  on the slower implementation to roughly 15-30 seconds per sample. Keep
  full fixed-profile training for correctness and time-to-quality results.
  Do not independently autorange the amount of learning in each language.
- Report forward, backward, optimizer, and cleanup costs from separate
  diagnostic runs. Headline timings have counters/profilers disabled.
  Do not subtract a sampled cleanup time from total to advertise speed.
- Add a small interop diagnostic: repeated affine/activation chains on
  tensors of 1, 64, 4,096, and 65,536 elements, with 16/128/512 operations
  per request. Use the same ATen operation sequence, out-of-place behavior,
  and verified final result. Include Python, x2c, and a minimal direct C++
  loop over that sequence. Count calls/results in a diagnostic build.
  The C++ control bounds host/wrapper costs; it is not another app framework.
- Distinguish matched-operation attribution from idiomatic user-level
  comparisons. Never compare expanded x2c affine operations with fused
  Python Linear and label the difference interop overhead. An optional
  compiled-Python comparison is a separately labelled follow-up, not the
  baseline or a claim that eager parity replaces `torch.compile`.

PyTorch's [benchmark guidance](https://docs.pytorch.org/docs/2.10/benchmark_utils.html)
supports warmup, controlled threads, repeated samples, and robust summaries.
Its [CPU threading notes](https://docs.pytorch.org/docs/2.10/notes/cpu_threading_torchscript_inference.html)
explain the thread controls. Reuse these measurement principles in the
common runner rather than imposing a Python-only timing method on one side.

## Memory experiment: four owners, two time scales

Measure both post-step retention and within-step peak. Scoped temporaries
may all disappear at step end yet keep much more native storage alive
during the step than Python's shorter-lived intermediate references.

Record these layers separately in diagnostic runs:

| Layer | Measurement and limit |
| --- | --- |
| Scope | Live allocations/scopes and cumulative call deltas; requested bytes are not live bytes. |
| Canonical pool | Root/current interned counts; active, backing, and depot bytes. Sample after returning to the same pool depth. |
| C++ wrappers | Created/destroyed/current/peak handles by type and returned handle arrays, across both handwritten and generated wrappers. |
| Process | Current RSS/physical footprint, sampled peak, and process high water; baseline before imports, after model setup, after warmup, and after teardown. |

Use existing Scope/Pool stats. If native attribution needs counters, add
private benchmark-only instrumentation at the handwritten wrapper creation,
generator's `xg_wrap` template, and matching frees, with separate diagnostic
objects. Regenerate through the generator. No public inspection API, no
counter overhead in ordinary builds, and no hand edits to generated files.
Sample macOS process metrics through a small benchmark-local native helper
using the installed SDK; Python can use the same helper via ctypes. Write
fixed numeric records to files/preallocated buffers: measurement must not
create an ever-growing stream of interned Strings or Lists.

Live handles are not live tensor storage: views, detach, module parameters,
and autograd share/retain native storage. Do not sum tensor `numel` values
and call it resident memory. Use profiler/allocation attribution only for
an unexplained result, separately from timings. Python garbage collection
remains normal in the headline runs; a forced collection at final teardown
is a separately labelled diagnostic, not a hidden advantage for one side.

Memory profiles:

1. **Steady training and inference:** model, data, and optimizer outside the
   step; ordinary documented scope per step/request. Use the same fixed
   shape and compare N, 2N, and 4N steps in fresh processes. Choose common N
   in a pilot so 4N takes roughly three minutes on the slower side. Repeat
   a suspicious slope once. Preload data and exclude growing result logs.
2. **Canonical churn:** include the documented parameter-enumeration forward,
   repeated `named_parameters`, generated tuple/list outputs, and a bounded
   cycle of batch shapes. Sample root-pool counts as well as Scope stats.
   If growth appears, compare an ordinary step with a nested List-pool
   bracket and with hoisted stable handles. Report the original behavior
   and the caller complexity required to improve it.
3. **Useful survivor:** create a large tensor, retain a small view/detached
   state across the inner scope using the documented move operation, read
   it after release, then release the survivor. A view intentionally pins
   its larger backing storage; compare a cloned small result. Never use
   an already released wrapper or assume List promotion moves its contents.
4. **Graph and scope granularity:** sequence windows and interop chains
   compare one natural request scope with safe shorter scopes. Subscopes
   must preserve gradients; detaching merely to lower memory is a different
   algorithm. Also test gradient accumulation over four microbatches,
   with backward per microbatch and one optimizer update on both sides.
5. **Repeated lifetime/error recovery:** 50 model/optimizer/scheduler
   create-train-save-load-destroy cycles using one overwritten checkpoint;
   bad shapes inside deferred scopes every 100 requests followed by valid
   work. Check output, mode restoration, and ownership baselines. Keep
   errors fixed-text for the base run; separate unique-message interning.
6. **Positive control:** retain a bounded set of large outputs and forward
   graphs without backward deliberately on both sides, observe growth,
   release them, and observe
   owner counters. Cap retained payload at 128 MiB. This proves the memory
   measurement sees a known problem; it is not an ordinary usage example.

A healthy fixed-workload result has stable owner counts after cleanup and
a bounded post-warmup memory envelope as iteration count increases. Report
bytes/1,000 steps, peak/steady footprint, and live-owner deltas. Rising
root-pool storage, unreleased native handles, graph retention, and allocator
caches require different explanations. RSS need not return to startup.
Warmup/cache growth is not automatically a leak; continuing growth is not
excused merely because Scope counts balance. Stop at the resource limits.

Report the x2c/Python within-step peak ratio even when neither leaks. A
repeatable excess above 2x in incremental workload memory, or growth with
scope length at fixed live mathematical state, requires attribution before
calling the memory model suitable. This is a review criterion for this
experiment, not a permanent gate or an automatic redesign mandate.

## Files, execution, and delivery

Add `packages/torch/benchmarks/` with `README.md`, one small fixed-profile
manifest, paired `tabular.x/.py`, `mnist.x/.py`, `sequence.x/.py`,
`interop.x/.py/.cpp`, `prepare.py`, `run.py`, and only the common input,
metrics, and plotting helpers actually shared. Each app runs on its own;
the runner launches it and summarizes numeric output, not model logic.
Use explicit modes `check`, `time`, and `memory` with output paths passed
in, rather than adding work to existing package targets. Document direct
commands. Keep datasets, binaries, checkpoints, and instrumentation under
an isolated `unittest/build/torch-comparison/` tree; full logs/raw samples
under `debug/torch-comparison/<run-id>/`. Do not disturb the ongoing
package agent's `packages/torch/builds` objects or output checkpoints.

Implementation sequence:

1. Snapshot current package state and coordinate M3 availability. Write
   both application sources and shared artifact/profile preparation.
   Pilot Python learning and compile/probe x2c operations before expanding
   the harness. Record genuine surface gaps; do not quietly fill them with
   benchmark-only C++ application logic.
2. Establish full-value correctness, resumed training, and resource caps.
   Resolve bugs in the authorized package work before interpreting ratios.
   Consequential runtime/API changes discovered here need a separate
   decision; preserve the reproducer and report the affected case meanwhile.
3. Implement memory sampling and positive control. Run ordinary scopes
   first; then only the targeted attribution/alternative-lifetime cases
   needed to explain a result. Do not optimize away evidence preemptively.
4. Run the paired timings and longer memory profiles in a quiet window.
   Budget about 30-60 minutes for the initial full CPU measurement session,
   excluding dependency preparation/builds; pilot first and record actual
   duration. If this exceeds the budget, split sessions or explicitly
   reduce a common profile, never silently omit a slow/failing language.
5. Produce `packages/torch/benchmarks/REPORT.md` plus standalone plots:
   learning curves, paired throughput, memory versus steps, and peak
   memory versus chain/window length. Include raw-data location/hashes,
   commands, exact builds, correctness tolerances/results, variability,
   portability edits, and unsupported cases. Give per-workload verdicts;
   no single aggregate speedup or inferred overall parity percentage.
6. Review and fix the authored sources and any resulting generated changes.
   Integrate current main and use the existing publication command for the
   final delivered tree. Benchmark results identify the measured source
   hashes; rerun affected comparisons if integration changes that path.
   Delivery follows root AGENTS.md. This planning request stops at this plan.

## Plan review

- Scope establishes wrapper ownership and finalizer execution; libtorch
  establishes kernel/autograd semantics. Neither establishes bounded
  canonical-pool storage or process footprint. Measure those independently
  rather than adding redundant runtime checks after successful operations.
- Reuse package modules/optimizers, generated ops, checkpoint exchange,
  Scope/Pool counters, and optional benchmark conventions. The small runner
  is needed to share artifacts, isolate processes, and compare results;
  it owns no tensor semantics, caches, alternate graph, or training engine.
- Models and forwards remain ordinary x2c functions and existing native
  operations. Scope/pool variants are evaluated as caller obligations, not
  introduced as an unproven automatic lifetime framework.
- Validators belong to this experiment: artifact/version matching prevents
  comparisons of different work; full-value checks catch wrong outputs;
  ownership/mode probes catch invalid lifetime/error behavior; resource
  caps bound intentional retention. Add no new production diagnostics or
  recurring test requirements. Missing API behavior is a reported gap.
- No performance win is assumed. A slowdown or a memory pathology is a
  valid and useful result; fixes must preserve the matched workload and
  be measured with their actual user-facing lifetime cost.
