# Former custom x2c shootout

This directory preserves the former fourteen-workload suite, its reference
programs, and compact calibration. Historical measurements remain in Git.
It includes modified workloads and locally written references, so it is not
a conforming Benchmarks Game
comparison. Its C-port column is historical and is not part of the current
comparison.

The active suite is [the official Benchmarks Game suite](../shootout/README.md).
The root `shoot-*` targets and performance snapshots use that suite only.
The instructions below describe the former suite.

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

## Historical results

The [saved report](https://github.com/gwf/x2c/blob/b46aa0e12ab1e4356bd6b4942f1fc30ade5faff6/examples/shootout-unofficial/results/current.md) and [raw result data](https://github.com/gwf/x2c/blob/b46aa0e12ab1e4356bd6b4942f1fc30ade5faff6/examples/shootout-unofficial/results/current.json)
remain in Git history. New promoted reports are ignored under
`examples/build/shootout-unofficial/results/current.*`.

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
python3 examples/shootout-unofficial/tools/shootout.py run
```

The command requires an optimized, non-LTO x2c build. It writes generated C,
executables, raw samples, and run details beneath the ignored
`examples/build/shootout-unofficial/` directory, then prints the normalized table. It
does not modify tracked files.

After reviewing a run, promote its report explicitly:

```sh
python3 examples/shootout-unofficial/tools/shootout.py update
```

Rebuild and measure C, x2c, and Python together only when the reference
sources, machine, toolchain, or methodology needs a new calibration:

```sh
python3 examples/shootout-unofficial/tools/shootout.py calibrate
```

Calibration rotates all three implementations through each order position,
then replaces `baseline.json` and the ignored promoted reports only after
every build, correctness check, warmup, and measurement succeeds. The compact
baseline keeps statistics, source identities, provenance, and correctness
hashes. Numeric tolerance checks retain their small expected values; raw
reference samples and exact-output copies stay in ignored run output.

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
