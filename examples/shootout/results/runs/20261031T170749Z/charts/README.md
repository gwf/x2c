# Run 20261031T170749Z

Published report revision: `4b881e60fd9c4492cea9947a57d072d18e04b5ef`.
Measured source revision: `06a81d6535120d6c0c07e320751548075c5d3fc1`.

This run follows the cached k-nucleotide loop-bound and ordinary parallel
fannkuch-redux experiments. Loop-bound candidate: **adopted**.
Parallel fannkuch candidate: **adopted**. The decision record and all source
variants remain in the evidence directory, including rejected candidates.

All 76 official fixture and local-output checks pass. Sixteen fresh-process
samples per program yield 1,216 observations. The common chart cohort remains
nine problems across all eight columns. Java includes fresh-JVM startup and
JIT compilation. Canonical-size timing remains unrun.

Timing began after six consecutive ten-second observations at least 90 percent
CPU idle. This establishes the pre-run window, not zero background activity
throughout timing. Exact samples, build/check receipts, source hashes, manifest,
baseline, and quiet evidence remain in `raw/`, `benchmarks.json`, and
`baseline.json.gz`. Native executables and external toolchains are not archived.
The parent [recovery guide](../../../README.md) describes rebuilding sources and
rendering saved results without the original checkout or temporary directories.

Parallelism follows [published-submission precedent](../../../threading.md) within the
existing idiomatic/tuned definitions. The eight-column comparison is retained;
no separate serial/parallel headline regimes are introduced.

## Separate full-run comparison

Comparison with `20261031T161720Z` uses median elapsed milliseconds. These are separate
full runs, not an alternating causal experiment; C reference drift is shown.

| Workload | Previous idiomatic ms | New idiomatic ms | C before ms | C after ms | Before/C | After/C |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fannkuchredux | 48.416 | 10.025 | 15.377 | 16.337 | 3.15 | 0.61 |
| knucleotide | 168.942 | 170.790 | 18.502 | 18.918 | 9.13 | 9.03 |

## Quiet paired source experiments

Each size uses sixteen alternating fresh-process pairs with one warmup per
program. All 160 probe observations, original and candidate sources,
compiler/runtime/binary hashes, build recipes, and quiet observations are in
`../../../evidence/bound-fann/`. The DNA input/oracle corpus is retained in
`../../../evidence/counter-spectral/inputs/`. The portable probe script reads that
versioned corpus. Active-desktop observations are retained separately.

| Experiment | Input N | Before elapsed ms | Candidate elapsed ms | Before CPU ms | Candidate CPU ms | Candidate wins / 16 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| knucleotide | 20000 | 43.841 | 42.313 | 42.926 | 41.739 | 11 |
| knucleotide | 100000 | 166.233 | 162.752 | 165.608 | 162.143 | 13 |
| fannkuchredux | 7 | 1.971 | 1.895 | 1.637 | 1.580 | 10 |
| fannkuchredux | 9 | 47.774 | 9.896 | 47.459 | 49.425 | 16 |
| fannkuchredux | 10 | 558.167 | 98.807 | 557.736 | 567.895 | 16 |

The loop-bound candidate caches `sequence.len() - width` without changing the
Map values or growing hash tables. The fannkuch candidate gives each ordinary
Thread private Arrays and a contiguous global permutation range. Factorial
rotation digits initialize both the permutation and countdown state. Checksum
sign uses global rank parity. The caller joins workers before reading each
Chunk's scalar checksum/maximum. N<9 uses the same calculation serially.
Ranges use 64-bit long arithmetic, including N=12 partition products.

Fannkuch matches the baseline and contributed C at N=2 through N=10, with three
runs of each source per size. All 5,912 ranks and their next-step continuations
for N=2 through N=7 match an independent recursive permutation generator.
The unchanged tuned entry remains serial and uses its existing typed Arrays.
No custom allocator, raw collection storage, or compiler/runtime edit is part
of these benchmark changes. Earlier complete sources, reports, and charts
remain immutable in prior runs. This is a program-strategy comparison, not a
single-core language ranking.

`charts/` retains all three eight-column chart forms plus the focused probe
comparison in PNG/SVG/PDF, with CSV, renderers, and provenance. `website.json`
is the portable public export; path-bearing raw receipts remain audit materials.
