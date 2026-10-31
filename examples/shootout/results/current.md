# x2c Benchmarks Game result

- Run: `20261031T170749Z`
- Baseline: `2d8b84188a41dd85`
- Profile: `local`
- Samples: 16 fresh-process x2c measurements after 1 warmup(s)
- `idiomatic` is `main.x`, using ordinary x2c collections and APIs.
  `tuned` is `tuned.x`, using typed containers and other
  x2c optimizations within the same official specification.
- C, Python, Rust, C++, Go, and Java are unchanged contributed programs.
  These are local measurements, not the official site's timings.
- Java starts a fresh JVM per sample, including startup and JIT compilation.
  The separate process warmup does not warm the measured JVM.
- Time uses C as the implicit 1.00 baseline; SLOC uses Python as the
  implicit 1.00 baseline. Larger values mean more cost.
- N/A means there is no admitted contribution for that problem.
- Summary rows use only the 9 problems shared by every column:
  nbody, spectralnorm, fannkuchredux, mandelbrot, fasta, revcomp, binarytrees, regexredux, pidigits

## Elapsed time / C

| Benchmark | C | idiomatic x2c | tuned x2c | Python | Rust | C++ | Go | Java |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| nbody | 1.00 | 2.06 | 2.09 | 77.51 | 1.94 | 0.99 | 1.00 | 2.18 |
| spectralnorm | 1.00 | 2.29 | 1.04 | 102.18 | 1.00 | 0.96 | 2.34 | 6.48 |
| fannkuchredux | 1.00 | 0.61 | 0.81 | 19.04 | 0.29 | 0.76 | 0.88 | 2.52 |
| mandelbrot | 1.00 | 1.12 | 1.02 | 42.28 | 0.27 | 1.28 | 1.09 | 4.01 |
| fasta | 1.00 | 2.47 | 1.77 | 9.35 | 1.20 | 0.48 | 1.48 | 4.75 |
| knucleotide | 1.00 | 9.03 | 4.00 | 3.86 | N/A | N/A | N/A | N/A |
| revcomp | 1.00 | 7.96 | 8.27 | 8.99 | 1.44 | 12.79 | 1.46 | 18.06 |
| binarytrees | 1.00 | 1.11 | 1.08 | 6.93 | 0.15 | 4.43 | 0.99 | 1.56 |
| regexredux | 1.00 | 1.37 | 1.37 | 14.95 | 0.28 | 0.63 | 3.94 | 3.44 |
| pidigits | 1.00 | 1.04 | 0.99 | 11.22 | 1.52 | 1.06 | 2.50 | 10.89 |
| **Median** | **1.00** | **1.37** | **1.08** | **14.95** | **1.00** | **0.99** | **1.46** | **4.01** |
| **Arithmetic mean** | **1.00** | **2.23** | **2.05** | **32.49** | **0.90** | **2.60** | **1.74** | **5.99** |

## Source lines / Python

| Benchmark | C | idiomatic x2c | tuned x2c | Python | Rust | C++ | Go | Java |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| nbody | 1.38 | 1.15 | 1.15 | 1.00 | 1.49 | 1.55 | 1.37 | 1.54 |
| spectralnorm | 1.11 | 2.06 | 1.28 | 1.00 | 1.94 | 0.97 | 1.22 | 1.17 |
| fannkuchredux | 1.38 | 2.16 | 1.02 | 1.00 | 2.71 | 1.31 | 1.27 | 1.13 |
| mandelbrot | 1.34 | 0.91 | 0.94 | 1.00 | 4.56 | 0.78 | 1.59 | 1.34 |
| fasta | 1.84 | 1.05 | 1.00 | 1.00 | 0.81 | 1.76 | 1.79 | 2.02 |
| knucleotide | 0.87 | 0.29 | 0.34 | 1.00 | N/A | N/A | N/A | N/A |
| revcomp | 2.32 | 1.38 | 1.03 | 1.00 | 3.68 | 1.41 | 1.74 | 4.32 |
| binarytrees | 4.71 | 2.04 | 2.04 | 1.00 | 2.54 | 1.88 | 1.83 | 1.83 |
| regexredux | 3.24 | 1.03 | 1.32 | 1.00 | 1.46 | 8.11 | 1.97 | 1.49 |
| pidigits | 1.05 | 1.84 | 1.88 | 1.00 | 2.02 | 1.16 | 2.00 | 2.26 |
| **Median** | **1.38** | **1.38** | **1.15** | **1.00** | **2.02** | **1.41** | **1.74** | **1.54** |
| **Arithmetic mean** | **2.04** | **1.51** | **1.30** | **1.00** | **2.36** | **2.10** | **1.64** | **1.90** |


The median and the mean are orientation aids, not composite scores.
Read individual workloads; these summaries are not a language ranking.
