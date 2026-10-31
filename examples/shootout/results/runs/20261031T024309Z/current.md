# x2c Benchmarks Game result

- Run: `20261031T024309Z`
- Baseline: `c777007be2f2d389`
- Profile: `local`
- Samples: 12 fresh-process x2c measurements after 1 warmup(s)
- `idiomatic` is `main.x`, using ordinary x2c collections and APIs.
  `tuned` is `tuned.x`, using typed containers and other
  x2c optimizations within the same official specification.
- C, Python, Rust, and C++ are adopted, unmodified contributed programs.
  These are local measurements, not the official site's timings.
- Time uses C as the implicit 1.00 baseline; SLOC uses Python as the
  implicit 1.00 baseline. Larger values mean more cost.
- N/A means there is no admitted contribution for that problem.
- Summary rows use only the 9 problems shared by every column:
  nbody, spectralnorm, fannkuchredux, mandelbrot, fasta, revcomp, binarytrees, regexredux, pidigits

## Elapsed time / C

| Benchmark | C | idiomatic x2c | tuned x2c | Python | Rust | C++ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| nbody | 1.00 | 2.95 | 2.01 | 80.18 | 1.96 | 1.00 |
| spectralnorm | 1.00 | 10.43 | 1.05 | 112.43 | 1.09 | 0.96 |
| fannkuchredux | 1.00 | 3.70 | 0.81 | 20.35 | 0.31 | 0.77 |
| mandelbrot | 1.00 | 1.11 | 1.01 | 46.50 | 0.27 | 1.29 |
| fasta | 1.00 | 4.45 | 1.82 | 10.01 | 1.20 | 0.47 |
| knucleotide | 1.00 | 9.14 | 3.99 | 3.66 | N/A | N/A |
| revcomp | 1.00 | 59.01 | 8.56 | 9.24 | 1.52 | 13.44 |
| binarytrees | 1.00 | 16.99 | 4.70 | 7.32 | 0.16 | 4.69 |
| regexredux | 1.00 | 5.33 | 1.37 | 15.25 | 0.29 | 0.64 |
| pidigits | 1.00 | 1.05 | 1.00 | 11.13 | 1.52 | 1.05 |
| **Median** | **1.00** | **4.45** | **1.37** | **15.25** | **1.09** | **1.00** |
| **Arithmetic mean** | **1.00** | **11.67** | **2.48** | **34.71** | **0.93** | **2.70** |

## Source lines / Python

| Benchmark | C | idiomatic x2c | tuned x2c | Python | Rust | C++ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| nbody | 1.38 | 1.02 | 1.15 | 1.00 | 1.49 | 1.55 |
| spectralnorm | 1.11 | 1.25 | 1.28 | 1.00 | 1.94 | 0.97 |
| fannkuchredux | 1.38 | 0.98 | 1.02 | 1.00 | 2.71 | 1.31 |
| mandelbrot | 1.34 | 0.91 | 0.94 | 1.00 | 4.56 | 0.78 |
| fasta | 1.84 | 0.84 | 1.00 | 1.00 | 0.81 | 1.76 |
| knucleotide | 0.87 | 0.28 | 0.34 | 1.00 | N/A | N/A |
| revcomp | 2.32 | 0.79 | 1.03 | 1.00 | 3.68 | 1.41 |
| binarytrees | 4.71 | 1.25 | 1.38 | 1.00 | 2.54 | 1.88 |
| regexredux | 3.24 | 0.95 | 1.32 | 1.00 | 1.46 | 8.11 |
| pidigits | 1.05 | 1.84 | 1.88 | 1.00 | 2.02 | 1.16 |
| **Median** | **1.38** | **0.98** | **1.15** | **1.00** | **2.02** | **1.41** |
| **Arithmetic mean** | **2.04** | **1.09** | **1.22** | **1.00** | **2.36** | **2.10** |


The median and the mean are orientation aids, not composite scores.
Read individual workloads; these summaries are not a language ranking.
