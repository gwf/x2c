# x2c Benchmarks Game result

- Run: `20261101T153737Z`
- Baseline: `53fdc5b1230c52ce`
- Profile: `local`
- Samples: 12 fresh-process x2c measurements after 1 warmup(s)
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
| nbody | 1.00 | 1.90 | 2.04 | 77.64 | 1.28 | 0.91 | 1.00 | 2.21 |
| spectralnorm | 1.00 | 3.51 | 1.22 | 50.31 | 1.16 | 1.49 | 0.86 | 9.72 |
| fannkuchredux | 1.00 | 2.88 | 1.10 | 19.86 | 0.80 | 0.78 | 2.47 | 12.04 |
| mandelbrot | 1.00 | 1.49 | 1.30 | 27.68 | 0.84 | 1.09 | 1.57 | 12.23 |
| fasta | 1.00 | 5.17 | 3.73 | 20.86 | 2.66 | 1.04 | 1.91 | 10.36 |
| knucleotide | 1.00 | 8.53 | 1.71 | 7.75 | N/A | N/A | N/A | N/A |
| revcomp | 1.00 | 6.79 | 3.40 | 8.91 | 1.43 | 12.47 | 1.48 | 17.62 |
| binarytrees | 1.00 | 1.02 | 1.02 | N/A | 0.14 | 0.31 | 0.71 | 1.48 |
| regexredux | 1.00 | 2.01 | 2.01 | 5.53 | 0.95 | 2.06 | 13.16 | 9.50 |
| pidigits | 1.00 | 1.01 | 0.96 | 1.42 | 1.00 | 1.05 | 2.53 | 11.02 |
| **Median** | **1.00** | **2.45** | **1.66** | **20.36** | **1.08** | **1.07** | **1.74** | **10.69** |
| **Arithmetic mean** | **1.00** | **3.10** | **1.97** | **26.53** | **1.26** | **2.61** | **3.12** | **10.59** |

## Source lines / Python

| Benchmark | C | idiomatic x2c | tuned x2c | Python | Rust | C++ | Go | Java |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| nbody | 1.38 | 1.15 | 1.15 | 1.00 | 2.26 | 1.62 | 1.37 | 1.54 |
| spectralnorm | 1.50 | 2.06 | 2.89 | 1.00 | 2.53 | 0.97 | 2.08 | 1.17 |
| fannkuchredux | 1.01 | 1.14 | 1.18 | 1.00 | 1.12 | 1.42 | 1.47 | 0.60 |
| mandelbrot | 2.09 | 1.67 | 1.70 | 1.00 | 4.42 | 2.24 | 2.00 | 1.42 |
| fasta | 2.11 | 1.05 | 1.00 | 1.00 | 0.81 | 1.76 | 2.61 | 2.02 |
| knucleotide | 0.87 | 0.41 | 0.47 | 1.00 | N/A | N/A | N/A | N/A |
| revcomp | 2.32 | 1.38 | 1.29 | 1.00 | 3.68 | 1.41 | 1.74 | 4.32 |
| binarytrees | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A |
| regexredux | 1.02 | 0.52 | 0.58 | 1.00 | 0.46 | 2.54 | 0.62 | 0.43 |
| pidigits | 0.87 | 1.52 | 1.56 | 1.00 | 2.87 | 0.96 | 1.65 | 1.87 |
| **Median** | **1.44** | **1.26** | **1.24** | **1.00** | **2.39** | **1.52** | **1.69** | **1.48** |
| **Arithmetic mean** | **1.54** | **1.31** | **1.42** | **1.00** | **2.27** | **1.62** | **1.69** | **1.67** |


The median and the mean are orientation aids, not composite scores.
Read individual workloads; these summaries are not a language ranking.
