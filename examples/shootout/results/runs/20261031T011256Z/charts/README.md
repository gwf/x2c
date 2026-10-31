# Runtime and source-size charts

These charts apply three established visual forms to the saved x2c shootout
calibration. They contain C, idiomatic x2c, optimized x2c, and Python, across
all ten adopted problems. They do not mix in any website timing data.

## Research

- Brad Chamberlain's [2018 Chapel interview](https://blog.lambdaclass.com/interview-with-brad-chamberlain-about-chapel-a-productive-parallel-programming-language/)
  shows normalized code-size/runtime scatter plots. The current
  [Chapel productivity page](https://chapel-lang.org/productive/) uses the
  same form. These are strong matches for the remembered visual comparison.
- Guillaume Marceau's May 30, 2009 article, *The speed, size and dependability
  of programming languages*, describes normalized scatter plots and shared-axis
  star plots: one mark per problem, with spokes meeting at each language's
  arithmetic centre. An indexed copy of the author's article supplied the
  method; the original gmarceau.qc.ca URLs returned errors during research.
  This reproduction uses logarithmic axes to retain every outcome rather
  than clipping slower programs, as the original charts did.
- The [official Benchmarks Game box plots](https://benchmarksgame-team.pages.debian.net/benchmarksgame/box-plot-summary-charts.html)
  show distributions of per-problem runtime ratios. The pinned upstream PHP
  implements quartiles as medians of halves, with numeric 1.5-IQR whiskers
  capped at the extrema. The reproduction uses that definition for the ten
  observations. Unlike the website's seven-problem summary, these charts
  include binary-trees, regex-redux, and pidigits as well.
- The [official source-size method](https://benchmarksgame-team.pages.debian.net/benchmarksgame/how-programs-are-measured.html#source-code)
  uses compressed source bytes. LOC is a different quantity. The first
  figure shows both, in separate panels.

## Data and interpretation

The source report is the checked-in `examples/shootout/results/current.json`,
run `20261031T011256Z`, measured on Apple M4 Max using the `local` profile.
Within each problem, each program's wall time is the median of twelve
fresh-process measurements after one warmup. These are not timings at the
larger canonical performance sizes.

Each problem's runtime is divided by the fastest of the four implementations.
LOC is divided by the shortest of the four; compressed bytes are divided by
the smallest. A baseline of 1 therefore means best among these four for that
specific problem. C need not have a ratio of exactly 1 in every problem.

- `runtime-source-size.*`: one geometric-mean point per implementation, across
  all ten normalized problem values. Smaller and faster is lower left.
- `implementation-profiles.*`: all ten individual outcomes for each
  implementation, on the same scales. Spokes meet at arithmetic centres,
  following the historical star-plot form. Smaller and faster is lower left.
- `runtime-loc-distributions.*`: boxes show the middle 50% of the ten problem
  ratios. Horizontal centre lines and printed values are medians. Every
  individual problem is also shown; these are not timing-sample distributions.

The CSV retains absolute elapsed seconds, source lines, and compressed bytes
as well as the normalized values. Provenance records the report digest and
baseline digest. No measurements were rerun to make these figures.

## Files

- [Summary PNG](runtime-source-size.png), [SVG](runtime-source-size.svg),
  [PDF](runtime-source-size.pdf)
- [Profiles PNG](implementation-profiles.png), [SVG](implementation-profiles.svg),
  [PDF](implementation-profiles.pdf)
- [Box plots PNG](runtime-loc-distributions.png),
  [SVG](runtime-loc-distributions.svg), [PDF](runtime-loc-distributions.pdf)
- [40 program outcomes](measurements.csv)
- [Data provenance](provenance.json)
- [Renderer](render.py)

Render again with Python, NumPy, and Matplotlib:

```sh
python3 render.py /absolute/path/to/results/current.json /absolute/output/directory
```

The repository source and saved measurements were left unchanged.
