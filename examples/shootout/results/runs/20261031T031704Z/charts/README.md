# Eight-column Benchmarks Game charts

Run `20261031T031704Z` uses the local profile on Apple M4 Max, with 16 fresh-process samples per program. All 76 admitted programs passed official fixtures and configured workload checks. These are local measurements, not the official website's measurements.

Columns: C, idiomatic x2c, tuned x2c, Python, Rust, C++, Go, and Java. All non-x2c contributions retain the exact pinned official archive bytes.

Go 1.27.3 and native ARM OpenJDK 27.0.1.0.3 were used for the added columns. Go uses standard compilation with CGO disabled. Java uses default JVM compilation and execution settings, with no in-process warmup. Every sample launches a fresh JVM and includes startup and JIT compilation. The separate warmup process does not warm the measured JVM. These results do not measure warmed steady-state Java throughput.

All charts use the nine problems shared by every column, for 72 plotted program outcomes. The complete measurements CSV also includes four k-nucleotide outcomes. Rust, C++, Go, and Java k-nucleotide cells are unavailable; the repository's reference-coverage report records header requirements and correctness failures. Missing outcomes are never treated as zero.

## Figures and data

- `runtime-source-size`: geometric-mean runtime versus LOC and compressed source size. Smaller values are better on both axes.
- `implementation-profiles`: nine individual outcomes per panel, with spokes to the arithmetic centre. Every panel has identical logarithmic axes.
- `runtime-loc-distributions`: Benchmarks Game-style box plots across problems, with all individual outcomes shown. Boxes show variation across problems, not timing uncertainty.
- Each figure is available as PNG, SVG, and PDF.
- `measurements.csv` contains 76 program outcomes; `summaries.csv` contains the eight geometric-mean summary points.
- `provenance.json` records report identity and metric definitions. `render.py` reproduces these artifacts from `examples/shootout/results/current.json`.

Per-problem values are normalized against the fastest, shortest, or smallest of the selected programs. The common nine-problem cohort is identical in every summary. Algorithms, threading, libraries, allocation, and implementation choices still matter; these are selected-program comparisons rather than general language rankings. For example, the contributed C binary-trees implementation uses parallel workers.

Source lines exclude blanks and comments, using language-aware comment removal. Gzip size uses comment-free source and collapsed code whitespace, retaining string contents. The local Mandelbrot dimension is 512 for every implementation. Canonical-size timing remains unrun.

Earlier four- and six-column artifacts remain in the sibling directories. Their runs, cohorts, or normalization may differ.

Chart references:

- [Benchmarks Game box plots](https://benchmarksgame-team.pages.debian.net/benchmarksgame/box-plot-summary-charts.html)
- [Source-size methodology](https://benchmarksgame-team.pages.debian.net/benchmarksgame/how-programs-are-measured.html#source-code)
- [Chapel runtime/source-size scatter example](https://blog.lambdaclass.com/interview-with-brad-chamberlain-about-chapel-a-productive-parallel-programming-language/)
