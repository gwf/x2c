# x2c Benchmarks Game result

- Run: `20261031T181939Z`
- Baseline: `479a192b239c39b8`
- Profile: `local`
- Samples: 56 fresh-process x2c measurements after 1 warmup(s)
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
- Summary rows use only the 8 problems shared by every column:
  nbody, spectralnorm, fannkuchredux, mandelbrot, fasta, revcomp, regexredux, pidigits

## Elapsed time / C

| Benchmark | C | idiomatic x2c | tuned x2c | Python | Rust | C++ | Go | Java |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| nbody | 1.00 | 2.04 | 2.07 | 79.25 | 1.29 | 0.91 | 1.01 | 2.20 |
| spectralnorm | 1.00 | 3.52 | 1.56 | 51.04 | 1.11 | 1.43 | 0.82 | 9.35 |
| fannkuchredux | 1.00 | 2.99 | 3.95 | 19.89 | 0.80 | 0.77 | 2.65 | 12.08 |
| mandelbrot | 1.00 | 3.88 | 3.47 | 28.40 | 0.85 | 1.09 | 1.60 | 12.23 |
| fasta | 1.00 | 5.68 | 4.05 | 21.39 | 2.64 | 1.05 | 1.93 | 10.41 |
| knucleotide | 1.00 | 9.62 | 8.31 | 7.58 | N/A | N/A | N/A | N/A |
| revcomp | 1.00 | 8.03 | 8.47 | 8.97 | 1.46 | 13.07 | 1.48 | 17.88 |
| binarytrees | 1.00 | 1.08 | 1.07 | N/A | 0.13 | 0.29 | 0.70 | 1.38 |
| regexredux | 1.00 | 4.58 | 4.52 | 5.31 | 0.94 | 2.08 | 13.59 | 9.41 |
| pidigits | 1.00 | 1.04 | 1.00 | 1.42 | 1.00 | 1.05 | 2.48 | 10.79 |
| **Median** | **1.00** | **3.70** | **3.71** | **20.64** | **1.06** | **1.07** | **1.76** | **10.60** |
| **Arithmetic mean** | **1.00** | **3.97** | **3.64** | **26.96** | **1.26** | **2.68** | **3.19** | **10.54** |

## Source lines / Python

| Benchmark | C | idiomatic x2c | tuned x2c | Python | Rust | C++ | Go | Java |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| nbody | 1.38 | 1.15 | 1.15 | 1.00 | 2.26 | 1.62 | 1.37 | 1.54 |
| spectralnorm | 1.50 | 2.06 | 1.28 | 1.00 | 2.53 | 0.97 | 2.08 | 1.17 |
| fannkuchredux | 1.01 | 1.14 | 0.54 | 1.00 | 1.12 | 1.42 | 1.47 | 0.60 |
| mandelbrot | 2.09 | 0.88 | 0.91 | 1.00 | 4.42 | 2.24 | 2.00 | 1.42 |
| fasta | 2.11 | 1.05 | 1.00 | 1.00 | 0.81 | 1.76 | 2.61 | 2.02 |
| knucleotide | 0.87 | 0.41 | 0.34 | 1.00 | N/A | N/A | N/A | N/A |
| revcomp | 2.32 | 1.38 | 1.03 | 1.00 | 3.68 | 1.41 | 1.74 | 4.32 |
| binarytrees | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A |
| regexredux | 1.02 | 0.32 | 0.42 | 1.00 | 0.46 | 2.54 | 0.62 | 0.43 |
| pidigits | 0.87 | 1.52 | 1.56 | 1.00 | 2.87 | 0.96 | 1.65 | 1.87 |
| **Median** | **1.44** | **1.14** | **1.01** | **1.00** | **2.39** | **1.52** | **1.69** | **1.48** |
| **Arithmetic mean** | **1.54** | **1.19** | **0.98** | **1.00** | **2.27** | **1.62** | **1.69** | **1.67** |


The median and the mean are orientation aids, not composite scores.
Read individual workloads; these summaries are not a language ranking.
