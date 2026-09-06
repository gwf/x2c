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

`main.x` and `ported.x` answer different questions. `main.x` asks what x2c
costs when the problem is expressed in x2c, so it uses the collections,
the literals, `match`, and `Scope`. `ported.x` asks whether x2c can be written
as a better C, so it keeps C's native arrays and inner loops and uses an x2c
feature only where the C was verbose: a `Scope` that deletes a `free` path, a
`%(...)` literal that replaces a constructor taking six positional arguments,
a value struct whose inline methods name repeated index arithmetic.

The gap between the two columns at any one benchmark is the run-time cost of
that benchmark's abstraction. Where both sit near `1.00`, the abstraction
cost nothing measurable.

The C and Python sources are checked in for review, attribution, and
occasional recalibration. An ordinary run does not build, import, or execute
them. It rebuilds x2c incrementally, checks and measures only the two x2c
programs, then compares their medians with the pinned C and Python statistics
in `baseline.json`. Those statistics are pinned to the exact bytes of `main.c`
and `main.py`, so neither reference may be edited, not even to add a comment,
without a full recalibration.

## Build and run one program

Each `main.x` and `ported.x` carries its own recipe as a header comment. The
references have none, because their bytes are pinned. From inside a benchmark
directory, using the `local` profile arguments that `benchmarks.json` records
for that benchmark:

```sh
cc -O2 -DNDEBUG main.c -lm -o /tmp/bench-c && /tmp/bench-c <args>
python3 main.py <args>
../../../../builds/0/x2c build -O2 -DNDEBUG --output /tmp/bench-x main.x
/tmp/bench-x <args>
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
