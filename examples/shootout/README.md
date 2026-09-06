# x2c language shootout

This optional example suite compares fourteen problems written twice in x2c
against equivalent C and Python references. Every implementation uses the same
algorithm and inputs, and produces the same output.

Each benchmark directory holds four programs:

| File | What it is |
| --- | --- |
| `main.c` | the C reference |
| `main.py` | the Python reference |
| `main.x` | the problem written in x2c |
| `ported.x` | the C ported to x2c, keeping C's representation |

`main.x` uses x2c where it makes the solution shorter or clearer, and keeps
ordinary C where it already fits. For example, CSV parsing reuses six stack
doubles, while binary trees use an array literal for each node. `ported.x`
keeps the C reference's representation and uses x2c where it simplifies the
code. Neither version needs to use a feature just to demonstrate it.

The timing difference between the columns reflects their representations,
allocation patterns, and generated code together; it does not isolate the
cost of any one language feature.

The C and Python sources are checked in for review, attribution, and
occasional recalibration. An ordinary run does not build, import, or execute
them. It rebuilds x2c incrementally, checks and measures only the two x2c
programs, then compares their medians with the pinned C and Python statistics
in `baseline.json`. Those statistics are pinned to the exact bytes of `main.c`
and `main.py`, so neither reference may be edited, not even to add a comment,
without a full recalibration.

## Current results

Local measurements from September 6, 2026: twelve fresh-process samples after
one warmup for each x2c program, compared with the saved C and Python
references. C and Python were not rerun. Lower ratios are better; C execution
time and Python source size each have a baseline of 1.00.

| Benchmark | Time x2c/C | Time ported/C | Time Python/C | SLOC x2c/Python | SLOC ported/Python | SLOC C/Python |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| nbody | 0.95 | 0.95 | 125.24 | 1.11 | 1.15 | 1.43 |
| spectralnorm | 0.95 | 0.93 | 110.56 | 1.69 | 1.69 | 1.65 |
| fannkuchredux | 0.76 | 0.74 | 20.13 | 1.29 | 1.46 | 1.74 |
| binarytrees | 2.28 | 0.94 | 3.84 | 1.53 | 1.65 | 2.53 |
| brainfuck | 0.97 | 0.97 | 57.75 | 1.29 | 1.33 | 1.60 |
| wordfreq | 5.22 | 0.99 | 8.22 | 1.60 | 2.80 | 3.24 |
| mandelbrot | 1.01 | 0.99 | 136.17 | 1.27 | 1.27 | 1.50 |
| sieve | 1.05 | 1.03 | 20.13 | 1.93 | 1.80 | 1.87 |
| matmul | 1.02 | 1.00 | 87.73 | 1.73 | 1.93 | 2.00 |
| gameoflife | 1.07 | 0.98 | 340.56 | 1.52 | 1.43 | 1.38 |
| quicksort | 1.02 | 1.03 | 16.41 | 1.20 | 1.13 | 1.13 |
| graphbfs | 1.23 | 2.70 | 3.20 | 1.69 | 1.59 | 1.69 |
| calculatorast | 11.00 | 0.98 | 77.36 | 1.30 | 2.13 | 1.87 |
| csvparse | 2.00 | 1.00 | 4.70 | 2.53 | 2.65 | 2.71 |
| **Median** | **1.04** | **0.99** | **38.94** | **1.53** | **1.62** | **1.72** |
| **Arithmetic mean** | **2.18** | **1.09** | **72.29** | **1.55** | **1.71** | **1.88** |

Every x2c program is faster than its saved Python reference in this run.
CSV parsing takes 122 ms versus Python's 287 ms (2.35 times faster); binary
trees takes 66 ms, about 1.68 times faster than Python. These are measurements
of these programs on this machine, not a general language ranking.

The [full report](results/current.md) and [raw result data](results/current.json)
record the run and its reference baseline. `make shoot-update` refreshes those
reports; this README table is a dated snapshot.

## Build and run one program

After building x2c, run this once from the repository root so the compiler
is available in subdirectories:

```sh
export PATH="$PWD:$PATH"
```

Each `main.x` and `ported.x` carries its own recipe as a header comment. The
references have none, because their bytes are pinned. From inside a benchmark
directory, using the `local` profile arguments that `benchmarks.json` records
for that benchmark:

```sh
cc -O2 -DNDEBUG main.c -lm -o /tmp/bench-c && /tmp/bench-c <args>
python3 main.py <args>
x2c run -O2 -DNDEBUG main.x -- <args>
```

## Run and update

From the repository root:

```sh
make shoot-run
```

The command requires an optimized, non-LTO x2c build. It writes generated C,
executables, raw samples, and run details beneath the ignored
`examples/build/shootout/` directory, then prints the normalized table. It
does not modify tracked files.

After reviewing a run, refresh the checked-in current result explicitly:

```sh
make shoot-update
```

Rebuild and measure C, x2c, and Python together only when the reference
sources, machine, toolchain, or methodology needs a new calibration:

```sh
make shoot-calibrate
```

Calibration rotates all three implementations through each order position,
then replaces `baseline.json`, `results/current.json`, and
`results/current.md` only after every build, correctness check, warmup, and
measurement succeeds.

## What the table means

Execution time uses C as the implicit `1.00` baseline. Source size uses Python
as the implicit `1.00` baseline:

- `Time x2c/C` is the current `main.x` median divided by the pinned C median.
- `Time ported/C` is the current `ported.x` median over the same C median.
- `Time Python/C` is the pinned Python median divided by the pinned C median.
- `SLOC x2c/Python` is live `main.x` SLOC divided by pinned Python SLOC.
- `SLOC ported/Python` and `SLOC C/Python` follow the same rule.

Larger values always mean more cost. The last two rows are the unweighted
median and arithmetic mean of each displayed factor. One benchmark runs far
slower than the rest and dominates the mean, so the median is the more useful
summary; both are orientation aids rather than composite scores.

Only the hand-written `main.c`, `main.py`, `main.x`, and `ported.x` are
counted. SLOC means nonblank lines after C-style comments are removed, so the
run recipe at the top of each x2c file does not count. Generated C and
launchers are excluded.

## Limits

The pinned reference timings assume the same machine family and performance
environment. The harness rejects a CPU-model or architecture mismatch unless
`SHOOTOUT_ALLOW_MACHINE_MISMATCH=1` is set, and records OS, power, load,
compiler, repository state, and binary hashes so weaker comparisons remain
visible. Results are not portable rankings across hosts.

The benchmark families and third-party notices are recorded in
[`THIRD_PARTY.md`](THIRD_PARTY.md).
