# Six-implementation Benchmarks Game charts

These charts use local run `20261031T024309Z`: 12 fresh-process timing samples per program on Apple M4 Max. They do not reuse timings from the Benchmarks Game website.

The columns are C, idiomatic x2c, tuned x2c, Python, Rust, and C++. All non-x2c programs are unchanged contributions from the pinned official source archive. All 58 admitted programs passed the official fixtures and configured workload checks.

Charts use the nine problems shared by all six columns (54 program outcomes). The complete measurements CSV also includes k-nucleotide for the original four columns. Rust k-nucleotide contributions fail lexical tie ordering. C++ k-nucleotide contributions require unavailable GNU PBDS headers; source inspection also finds tie-ordering issues. Missing cells are not zeroes.

## Figures

- `runtime-source-size`: geometric-mean runtime versus source lines, and versus compressed source size. Smaller values are better on both axes.
- `implementation-profiles`: individual problem outcomes, with spokes to the arithmetic centre. Every panel has the same logarithmic axes. Faster programs appear to the left; shorter programs appear toward the bottom.
- `runtime-loc-distributions`: Benchmarks Game-style runtime and source-line box plots. Boxes describe variation across problems, not timing uncertainty. All problem outcomes are shown.

Each figure is supplied as PNG, SVG, and PDF. `measurements.csv` contains all 58 outcomes; `summaries.csv` contains the six geometric-mean summary points. `provenance.json` records the report and rendering provenance. `render.py` reproduces the figures from `examples/shootout/results/current.json`.

Normalize each problem against the fastest, shortest, or smallest of these selected programs. The geometric means use the same nine problems in every column. These are comparisons of selected programs, not general language rankings.

Source lines exclude blank and comment-only lines. Python comments are removed with Python tokenization, preserving floor division and string contents. Source-size accounting was corrected after timing collection; the measured programs and runtime samples are unchanged. The harness records separate source-metric provenance. Gzip source size removes comments and collapses whitespace while retaining string contents.

The local Mandelbrot dimension is 512 in every language, matching the selected unchanged Rust program's multiple-of-eight requirement. The full canonical input profile has not been timed.

The C-through-x2c sanity check is separate from timing. All ten programs pass the native C driver; seven also pass x2c parsing, emitted-C compilation, official fixtures, and local-output parity. The tracked report names three parser limits.

Chart references:

- [Benchmarks Game box-plot charts](https://benchmarksgame-team.pages.debian.net/benchmarksgame/box-plot-summary-charts.html)
- [Benchmarks Game source measurement](https://benchmarksgame-team.pages.debian.net/benchmarksgame/how-programs-are-measured.html#source-code)
- [Chapel runtime/source-size scatter example](https://blog.lambdaclass.com/interview-with-brad-chamberlain-about-chapel-a-productive-parallel-programming-language/)

The earlier four-column artifacts remain in the sibling `shootout-charts` directory. Their cohort and normalization differ from these figures.
