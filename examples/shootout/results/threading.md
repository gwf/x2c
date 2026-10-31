# Parallel workers in the comparison

The Benchmarks Game permits parallel implementations where the individual
problem specification permits them. It does not require all contributions to
use the same number of cores. The official project explicitly includes
[parallel-programming choices](https://benchmarksgame-team.pages.debian.net/benchmarksgame/sometimes-people-just-make-up-stuff.html)
among the differences its program comparisons can expose.

Permission is workload-specific. The
[fannkuch-redux specification](https://benchmarksgame-team.pages.debian.net/benchmarksgame/description/fannkuchredux.html)
describes parallel chunks and atomic task scheduling. The
[pidigits specification](https://benchmarksgame-team.pages.debian.net/benchmarksgame/description/pidigits.html)
requires its step-by-step single-threaded algorithm. Therefore, parallelism is
not a blanket license to change every workload.

## What the adopted C binary-trees program does

Our pinned [C source](../benchmarks/binarytrees/main.c) starts one pthread for
each tested tree depth. Each worker independently allocates, checks, and frees
its assigned trees. The main thread joins workers and prints their results in
depth order. Stretch-tree and long-lived-tree work remains serial. At the local
input depth 14, the program starts six workers for depths 4 through 14.
Parallel execution can reduce elapsed time; the source alone does not establish
its speedup on this host.

The [binary-trees specification](https://benchmarksgame-team.pages.debian.net/benchmarksgame/description/binarytrees.html)
requires full trees, allocated leaves, and the specified allocation workload.
It forbids custom arenas or pools. It does not require one thread, and the
project publishes parallel C entries. Our adoption preserves the pinned
contribution rather than rewriting its execution strategy.

## Ordinary parallel x2c binary-trees

Both x2c binary-trees entries now use one ordinary `Thread` per depth batch,
matching the adopted C strategy. An ordinary Array retains Batch objects. Each
Batch stores depth, iteration count, worker handle, and scalar check. The worker
reads its initialized inputs and writes only its own check. The coordinator
joins each worker before reading its result and prints in depth order.

Each worker allocates full Node trees, including every leaf, with the existing
runtime allocator and worker-local Scope regions. Each iteration releases its
temporary tree. Stretch and long-lived work remains serial. There is no custom
allocator, typed container, raw collection storage, or shared mutable tree.
The callback returns void; its scalar check stays in the caller-owned Batch.

The unchanged [serial source](../benchmarks/binarytrees/serial.x) remains
executable. Earlier complete serial reports and charts remain immutable. The
latest run adds sixteen alternating same-compiler serial/parallel pairs at
depth 14, with one warmup per program and six workers in the parallel version.
The saved comparison includes elapsed time and total user-plus-system CPU time,
raw samples, output checks, source and binary hashes, and quiet-window evidence.

Parallelism is independent of the idiomatic/tuned distinction. Both columns use
the same ordinary threading code here. Other workloads retain their previous
execution strategies. These charts still compare selected contributions with
mixed serial and parallel programs, rather than controlled single-core language
implementations. The
[official measurement method](https://benchmarksgame-team.pages.debian.net/benchmarksgame/how-programs-are-measured.html)
also distinguishes elapsed time from CPU time.

The pre-run quiet window does not establish zero background activity throughout
measurement. Canonical-size timing remains unrun.
