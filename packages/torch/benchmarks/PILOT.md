# Pilot measurements

Every number below was measured on 2026-09-09 in this worktree. This is
the pilot: one fresh-process pair per timed configuration, not the plan's
five samples. It proved the harness, recorded the tolerances that passed
and failed, and named the gaps.

**`REPORT.md` supersedes this file for results.** It comes from the full
five-sample session, and three things it settles were open here: where
the two float32 trajectories part, what the interop cost at 65,536
elements is made of, and inter-op thread control. This file is kept as
the record of what the first pass saw and how the gaps were found.

## What ran

- Tree `c404f92285095a5d347a32c393e5234e0de62078` plus the uncommitted
  `packages/torch/benchmarks/` sources; `x2c 0.12.0`.
- macOS arm64, Apple M-series, 12 logical cores; torch `2.10.0`.
- Primary attribution lane: the x2c programs and the C++ control link the
  libtorch dylibs inside the pinned wheel at
  `/Users/gary/Git/Bonsai-demo/.venv/lib/python3.11/site-packages/torch/lib`,
  so both languages call the same backend binary. `libtorch_cpu.dylib`
  is 214,082,912 bytes, SHA-256 `941f3e16a8e02b23`; the full library and
  artifact hashes are in `debug/torch-comparison/pilot/environment.json`.
- The shipped lane, the package's own prepared prefix, was confirmed
  separately: the same `check` run passed identically there. The two
  distributions are not the same binary. `libtorch_cpu.dylib` is
  214,082,912 bytes in both, but SHA-256 `941f3e16` in the wheel and
  `4f03f832` in the prepared prefix, which is why the timings above name
  the primary lane.
- Intra-op threads 1 and 4, `X2C_TORCH_THREADS` on both sides.
- The machine was not otherwise idle-guaranteed. With one sample per
  configuration these ratios are indicative, not final.

Artifacts (SHA-256 prefixes, full values in
`unittest/build/torch-comparison/artifacts/config.json`):
`tabular-data.pt a9465db4`, `tabular-init.pt bf60a529`,
`tabular-batches.pt ebaf4a53`, `sequence-data.pt 72665ed7`,
`sequence-init.pt 939cffb5`, `interop-init.pt 7d2ca9e5`,
`mnist-init.pt 8f855dfc`, `mnist-batches.pt d13f17c6`. The MNIST IDX
files under `/tmp/mnist-real` are hashed into the same file.

## Correctness

The decisive check is one update with every value kept. It passed exactly
in all four lanes: **every tensor bit-identical, worst absolute difference
0.0**, against a tolerance of `atol=1e-6, rtol=1e-4`.

| Lane | Tensors compared after one update | Worst absolute |
| --- | --- | --- |
| tabular | 14 (output, loss, 6 gradients, 6 parameters) | 0.0 |
| mnist | 32 (output, loss, 12 gradients, 12 parameters, 6 buffers) | 0.0 |
| sequence | 12 (loss, state, 5 gradients, 5 parameters) | 0.0 |
| interop | 12 chain results, all element/operation pairs | 0.0 |

Task quality, and the plan's `1e-3` relative loss tolerance:

| Lane | x2c | Python | Relative | Verdict |
| --- | --- | --- | --- | --- |
| tabular trained val MSE | 0.032104194 | 0.032085128 | 5.9e-4 | ok |
| tabular resumed val MSE | 0.032104194 | 0.032085128 | 5.9e-4 | ok, resume equals uninterrupted in each language |
| tabular explicit val MSE | 0.032052495 | 0.032124087 | **2.2e-3** | **over the 1e-3 tolerance** |
| tabular untrained / mean baselines | 0.363178 / 0.331113 | identical | 0.0 | trained beats both |
| mnist test accuracy | 0.9865 | 0.9861 | 0.04 pp | ok; target 95%, gap limit 0.5 pp |
| mnist reloaded accuracy | 0.9865 | 0.9861 | - | reload reproduces predictions, buffers included |
| mnist untrained accuracy | 0.0874 | 0.0874 | 0.0 | - |
| sequence trained val MSE | 0.052508756 | 0.052508751 | 1.0e-7 | ok |
| sequence resumed val MSE | 0.052497877 | 0.052497871 | 1.1e-7 | ok |
| sequence baselines | untrained 0.329140, mean 0.297807, last-value 0.002132 | identical | 0.0 | trained beats untrained and mean; **last-value wins**, and is reported as the plan requires |
| sequence window 8 / 32 / 128 | 0.140526 / 0.141791 / 0.141082 | agree to 3.8e-8 | - | - |
| sequence 4-microbatch accumulation | 0.141791244 | 0.141791244 | 5.6e-9 | ok |
| mnist / tabular data checksums | exact | exact | 0.0 | the Python IDX reader matches `Torch.mnist` bit for bit |

Long-run per-weight equality is reported, not required. After 1,024
tabular updates the parameters differ by up to 6.8e-2 absolute and the
predictions by 6.5e-2; after 1,876 MNIST batches the BatchNorm running
statistics differ by up to 1.5e-1. The sequence lane, which is much
smaller, still agrees to 1.2e-7 after 512 windows.

### Settled since: where the float32 trajectories part

**Resolved.** The `trace` mode and `firstdiff.py` located it exactly: the
two Adam implementations are not the same sequence of float32 operations.
`REPORT.md` has the attribution and the reproducer. The bisection below
is what the pilot could see before the trace mode existed.

#### What the pilot saw

One update is bit-identical, yet the two trainings drift. Bisecting the
tabular lane, the evaluated loss is bit-identical through 24 updates and
differs from 28 onward:

```sh
work=unittest/build/torch-comparison
X2C_TORCH_THREADS=1 $work/bin/tabular time $work/artifacts $work/out native 24   # same
X2C_TORCH_THREADS=1 $work/bin/tabular time $work/artifacts $work/out native 28   # differs, 1.1e-7
python3 packages/torch/benchmarks/tabular.py time $work/artifacts $work/out native 28
```

Each language is deterministic across repeated runs (three runs each,
identical to every printed digit). The first difference is 1-2 ulp of a
float32 loss and it amplifies through ReLU sign flips. The `native` and
`explicit` variants diverge at the same update count and by the same
amount, so the source is common to both, not the forward's spelling. The
originating operation is not yet isolated; that is a numerical-attribution
task for the full pass, and no tolerance was relaxed to accommodate it.
The `explicit` lane's 2.2e-3 long-run loss difference above is recorded as
a failed tolerance for the same reason.

## Timing, one pair per configuration

`python/x2c` above 1 means x2c finished first. Counts are the pilot's, not
the plan's 15-30 second calibration.

| Lane | Threads | Count | x2c (s) | Python (s) | python/x2c |
| --- | --- | --- | --- | --- | --- |
| tabular native | 1 | 20,000 updates | 3.825 | 4.952 | 1.29x |
| tabular native | 4 | 20,000 | 5.279 | 6.069 | 1.15x |
| tabular explicit | 1 | 20,000 | 4.145 | 5.144 | 1.24x |
| tabular explicit | 4 | 20,000 | 5.269 | 6.354 | 1.21x |
| tabular predict1 | 1 | 20,000 requests | 0.168 | 0.313 | 1.87x |
| tabular predict1 | 4 | 20,000 | 0.165 | 0.316 | 1.91x |
| tabular predict32 | 1 | 10,000 | 0.186 | 0.281 | 1.52x |
| tabular predict32 | 4 | 10,000 | 0.177 | 0.271 | 1.54x |
| tabular predict256 | 1 | 2,000 | 0.133 | 0.140 | 1.05x |
| tabular predict256 | 4 | 2,000 | 0.190 | 0.196 | 1.03x |
| mnist epoch | 1 | 300 batches | 3.820 | 3.960 | 1.04x |
| mnist epoch | 4 | 300 | 2.874 | 2.829 | 0.98x |
| sequence window32 | 1 | 400 windows | 0.653 | 0.859 | 1.32x |
| sequence window32 | 4 | 400 | 0.666 | 0.843 | 1.27x |
| interop chain | 1 | 100 requests x 12 pairs | 7.774 | 1.644 | **0.21x** |
| interop chain | 4 | 100 | 9.542 | 3.153 | **0.33x** |

MNIST throughput at one thread: x2c 5,026 images/second, Python 4,848.
Peak process footprint during that run: x2c 700 MB, Python 680 MB, both
holding the 188 MB normalized training set.

Four intra-op threads made the tabular MLP *slower* on both sides at batch
128, and helped only MNIST. That is the workload, not the languages.

### The interop result, and what it is made of

Per chain step, nanoseconds, one thread (a step is `mul`, `add`, `relu`):

| Elements | Ops | C++ control | x2c | Python |
| --- | --- | --- | --- | --- |
| 1 | 16 / 128 / 512 | 830 / 761 / 760 | 948 / 1011 / 972 | 1246 / 1138 / 1129 |
| 64 | 16 / 128 / 512 | 780 / 754 / 742 | 886 / 905 / 920 | 1307 / 1146 / 1113 |
| 4,096 | 16 / 128 / 512 | 1392 / 1336 / 1313 | 1694 / 1733 / 4016 | 1825 / 1688 / 1681 |
| 65,536 | 16 / 128 / 512 | 18,706 / 18,514 / 18,494 | 46,629 / 85,545 / 76,174 | 19,175 / 18,823 / 15,734 |

At 1 to 4,096 elements x2c sits between the C++ control and Python, which
is the expected shape: a thin wrapper costs less than an interpreter. At
65,536 elements x2c costs 2.5x to 4.6x the control while Python matches
it, and the cost grows with chain length.

The memory sample explains the size of the live set, if not yet all of the
time. For the 512-operation chain on 65,536 elements:

```
sample chain-done 512 ... footprint 71.3 MB  peak 347.1 MB  RSS peak 2.01 GB
```

Every intermediate stays alive until the request scope closes: 512 steps
times three results times 256 KB is about 393 MB of live tensors, against
Python's three. Live Scope allocations return to 39 after each phase, so
nothing leaks; the cost is retention, not a leak. A short-scope variant in
the same run (32 blocks of 16 operations, only the running value carried
by `Scope.move`) does the same 512 operations at 58 microseconds per step
against the single-scope run's 75, so shorter scopes recover part but not
all of the difference. **Resolved since:** the remaining gap is retention too, and nothing is
unattributed. `run.py attribute` runs the chain under one lifetime per
process with the handle counters on: one scope per operation, carrying
only the running value, holds 14 tensor handles and a flat footprint at
every chain length and runs at parity with the C++ control. See
`REPORT.md`.

## Memory

Steady state, profile 1, 512 training steps then 512 requests at fixed
shape:

| | x2c | Python |
| --- | --- | --- |
| baseline before load | 61.4 MB | 158.4 MB |
| after setup and warmup | 137.5 MB | 251.6 MB |
| after 512 steps | 140.0 MB | 250.6 MB |
| after 512 requests | 140.5 MB | 252.2 MB |
| peak footprint | 140.5 MB | 252.2 MB (0.56x) |
| live Scope allocations, first to last step | 54 -> 54 | n/a |
| canonical pool active bytes | 17,408 -> 17,408 | n/a |

Both are flat: about 2.5 MB over the first 160 steps and nothing after, so
roughly **0 bytes per 1,000 steps** once warm, with owner counts stable.
x2c's whole-process footprint is a little over half Python's, mostly the
interpreter and `libtorch_python.dylib`.

Profile 5, 512 create-train-save-load-destroy cycles over one overwritten
checkpoint, with a bad shape injected inside a deferred scope every 100
requests: x2c 125.0 -> 134.1 MB, peak 140.6 MB; Python 176.4 -> 244.7 MB,
peak 253.9 MB. Live Scope allocations stayed at 46 for all 512 cycles and
the injected error was caught, the model's mode restored, and valid work
ran afterwards on both sides. **One thing does grow:** the canonical pool's
active bytes go 13,312 -> 46,080 across the 512 cycles, about 64 bytes per
cycle, because each cycle builds its checkpoint path with `%"$dir/$name"`
and Strings survive scope release. Hoisting the path out of the loop is
the obvious remedy; that was not measured here.

Profile 3, a survivor: a 67 MB tensor is created in an inner scope, a
16-row view and a 16-row clone are carried out of it with `Scope.move`,
the scope is released, both are read, then each carrier is destroyed. The
view reads correctly after the release and the clone still reads correctly
after the view's carrier is destroyed, which is the point. Neither
language's footprint fell when the backing storage was dropped (x2c 194.2
MB, Python 244.3 MB, unchanged across the release): the allocator kept the
region. That is symmetric, so it is an allocator behavior, not an x2c
retention.

Profile 4, sequence, peak growth with truncation length (64 windows each):

| Window | x2c | Python |
| --- | --- | --- |
| 8 | +2.3 MB | +2.1 MB |
| 32 | +8.2 MB | +1.8 MB |
| 128 | +25.4 MB | +14.7 MB |

Live Scope allocations ended at 64 with 5 live scopes, unchanged from the
start. x2c grows faster with window length for the same reason as interop:
inside a window every intermediate wrapper is alive, while Python frees the
ones the graph does not need.

Profile 6, the positive control. Both languages retained forward graphs
without backward until the 128 MiB payload cap at 120 iterations, then
released them:

| | x2c | Python |
| --- | --- | --- |
| after load | 127.6 MB | 177.9 MB |
| at 120 retained | 906.5 MB | 561.3 MB |
| after release | 180.0 MB | 207.9 MB |
| growth per retained graph | 6.45 MB | 3.20 MB |
| live Scope allocations | 46 -> 903 -> 53 | n/a |

The measurement sees the known problem, and the counters return. The 2.02x
ratio is attributed: Python holds the activations the graph needs, and x2c
additionally holds every pre-activation intermediate, because its wrapper
lives until the enclosing scope closes. For this shape the graph needs
2048x256 and 2048x128 float32 activations, 3.2 MB, and the pre-ReLU
results are another 3.2 MB.

**Review criterion.** The plan asks for attribution whenever the within-step
peak ratio repeatably exceeds 2x. It does in exactly one place, deliberate
retention inside a single long scope, and the attribution above is
complete. Ordinary steady training and inference are 0.5x, in x2c's
favour.

## Gaps found

1. **A `#define` numeric constant does not resolve an operator row.**
   `(images - MEAN) / STD` with `#define MEAN 0.1307` emits the C text
   `(images - MEAN) / STD` and fails to compile with "invalid operands to
   binary expression ('torch__Tensor' and 'double')". A `double` local
   works. This is the `%(...)`-symbol gotcha reaching operator overload
   resolution. Reproducer: `#define M 0.5` then
   `Tensor y = Tensor.zeros(%(2 2), XT_FLOAT32) - M;`. Worked around in
   `mnist.x` with two `double` locals.

2. **`Checkpoint.save` segfaults on a released Tensor.** A `Map` outlives
   the scope that created the Tensors it refers to, so storing a Tensor in
   a Map, releasing its scope, then saving crashes inside
   `xt_tensors_save_pickle` at `tensors[i]->t.detach()` rather than
   raising `<bad-state>`. Reproducer:

   ```x2c
   Map values = %{};
   Scope.retain();
   { defer Scope.release(); values["x"] = Tensor.zeros(%(2 2), XT_FLOAT32); }
   Checkpoint.save(values, "/tmp/crash.pt");   /* EXC_BAD_ACCESS */
   ```

   Using a released wrapper is a documented caller error, so this is a
   robustness question, not a defect: yyjson raises `<bad-state>` for the
   same class of stale access. Recorded, not fixed.

3. **No `set_num_interop_threads`.** *Closed.* The package now publishes
   `Torch.set_num_interop_threads` and `Torch.num_interop_threads`, and
   every program in the suite pins the count to 1 before any work and
   records what it got. The pilot's numbers above were measured with
   libtorch's default inter-op pool on the x2c side; for these
   single-stream eager workloads that pool is idle, and the session's
   numbers in `REPORT.md` were measured with it pinned on both sides.

4. **No per-type native handle counters.** *Closed.* The private,
   benchmark-only instrumentation the plan describes is now in place at
   the hand-written wrapper, the generator's `xg_wrap` template, the
   returned handle arrays, and every matching free, behind
   `XT_HANDLE_COUNTERS` with the reader in a separate diagnostic object.
   `benchmarks/README.md` describes it. It is what made the interop
   attribution possible.

5. **A composed root has no forward, so the tabular lane looks up its
   children once.** `Module.composed()` raises on `forward`, so the
   application holds a `List` of the three children rather than calling
   the root. That is fine and it is what `Module.sequential` was added
   for, but the MLP lane deliberately keeps the composed form the package
   README documents, so the difference is noted rather than removed.

No package change was needed to run any lane, and no package source was
edited.

## What the pilot left, and where it went

- Five fresh-process pairs per configuration in a quiet window, with the
  counts calibrated to about 15 seconds on the slower side - done, in
  `REPORT.md`.
- The shipped-prefix lane, to confirm the package's own build agrees -
  done: the same `check` run passes identically on both prefixes.
- Isolating the first float32 difference - done, and it is the optimizer.
- Attributing the interop cost at 65,536 elements - done, and it is
  retention.
- `REPORT.md` and the four plots - done, from `run.py report` and
  `plots.py`.
