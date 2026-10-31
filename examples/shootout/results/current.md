# x2c Benchmarks Game result

- Run: `20261031T011256Z`
- Baseline: `d985eacc9290a8a0`
- Profile: `local`
- Samples: 12 fresh-process x2c measurements after 1 warmup(s)
- `idiomatic` is `main.x`, using ordinary x2c collections and APIs.
  `optimized` is `optimized.x`, using typed containers and other
  x2c optimizations within the same official specification.
- C and Python are adopted, unmodified contributed programs.
  These are local measurements, not the official site's timings.
- Time uses C as the implicit 1.00 baseline; SLOC uses Python as the
  implicit 1.00 baseline. Larger values mean more cost.

| Benchmark | Time idiomatic/C | Time optimized/C | Time Python/C | SLOC idiomatic/Python | SLOC optimized/Python | SLOC C/Python |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| nbody | 2.79 | 2.07 | 75.44 | 0.95 | 1.06 | 1.28 |
| spectralnorm | 9.71 | 1.03 | 100.41 | 1.00 | 1.02 | 0.89 |
| fannkuchredux | 3.46 | 0.80 | 19.06 | 0.83 | 0.87 | 1.17 |
| mandelbrot | 1.11 | 1.02 | 41.54 | 0.81 | 0.83 | 1.19 |
| fasta | 4.25 | 1.76 | 9.22 | 0.75 | 0.90 | 1.65 |
| knucleotide | 9.25 | 4.00 | 3.96 | 0.28 | 0.33 | 0.84 |
| revcomp | 52.79 | 8.03 | 8.94 | 0.71 | 0.92 | 2.08 |
| binarytrees | 17.37 | 4.79 | 7.42 | 0.94 | 1.03 | 3.53 |
| regexredux | 5.16 | 1.37 | 15.21 | 0.78 | 1.09 | 2.67 |
| pidigits | 1.05 | 1.00 | 11.47 | 1.65 | 1.69 | 0.94 |
| **Median** | **4.70** | **1.56** | **13.34** | **0.82** | **0.97** | **1.24** |
| **Arithmetic mean** | **10.69** | **2.59** | **29.27** | **0.87** | **0.97** | **1.62** |

The median and the mean are orientation aids, not composite scores.
Read individual workloads; these summaries are not a language ranking.
