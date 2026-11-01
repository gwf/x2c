# Quiet-machine rerun after idiomatic tuning

Measured revision: `68156a1c6b9df92cdcd720aa4cc9735fff2831cf` (dev).
Run: `20261031T035446Z`, local profile on Apple M4 Max.

Builds and official fixtures passed for all 76 admitted programs. Timing began after six consecutive 10-second CPU observations exceeded 90 percent idle: 93.59, 90.59, 93.24, 91.12, 95.14, and 95.20 percent. Observations span 03:53:51-03:54:46 UTC on 2026-10-31. This establishes the pre-run quiet window; it is not a claim of zero background activity throughout measurement. The machine receipt retains the observations and one-off orchestration hash.

The complete calibration measured 76 programs x 16 fresh-process samples = 1216 observations. All local workload outputs matched. Charts use the same nine problems across all eight columns, for 72 program outcomes. K-nucleotide retains four available columns and is omitted from every chart summary. Missing outcomes are not zeroes.

## Changed idiomatic entries

These are whole-program local medians compared with the prior run `20261031T031704Z` at `0a7dbe5f1`. The preceding and current runs are separate observations, not an alternating causal experiment. C reference drift is shown alongside x2c changes.

| Problem | Idiomatic before ms | Idiomatic after ms | C before ms | C after ms | Idiomatic/C before | Idiomatic/C after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| nbody | 93.030 | 66.003 | 32.805 | 33.507 | 2.84 | 1.97 |
| fasta | 37.493 | 29.779 | 8.888 | 8.104 | 4.22 | 3.67 |
| regexredux | 204.786 | 52.966 | 39.006 | 38.888 | 5.25 | 1.36 |

N-body precomputes the ten Body pairs, FASTA reuses Buffers between output lines, and regex-redux enables the existing Regexp JIT API. The x2c source changes were already on dev; this task updates measurements and plots only. The tuned programs and contributed reference sources are unchanged. `comparison.csv` includes every x2c row from both runs.

## Figures and data

- `runtime-source-size`: geometric-mean elapsed time versus LOC and compressed source size.
- `implementation-profiles`: individual outcomes with spokes to the arithmetic centre, on identical logarithmic axes.
- `runtime-loc-distributions`: Benchmarks Game-style box plots with all individual outcomes. Boxes describe variation across problems, not timing uncertainty.
- Each figure is available as PNG, SVG, and PDF.
- `measurements.csv`: 76 program outcomes; `summaries.csv`: eight geometric-mean points; `comparison.csv`: before/after x2c outcomes.
- `provenance.json`: report hash, revision, quiet observations, cohort, and metric definitions.
- `render.py`: reproduce figures from `examples/shootout/results/current.json`.

Java launches a fresh JVM for every sample. Times include JVM startup and JIT compilation; the separate process warmup does not warm the measured JVM. These results do not measure warmed steady-state Java throughput. Non-x2c programs retain exact pinned official contribution bytes.

Per-problem normalization uses the fastest, shortest, or smallest selected program. Algorithms, threading, libraries, and implementation choices matter; these are selected-program comparisons, not general language rankings. Source lines exclude blanks and comments using language-aware removal. Gzip size retains string contents while removing comments and collapsing code whitespace. The local Mandelbrot dimension remains 512 in every language. Canonical-size timing remains unrun.

Earlier eight-column artifacts remain unchanged in the sibling `shootout-eight-columns` directory.
