# x2c Benchmarks Game result

- Run: `20261031T035446Z`
- Baseline: `7aa02ea1565e990a`
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
| nbody | 1.00 | 1.97 | 1.97 | 76.26 | 1.91 | 1.00 | 0.99 | 2.28 |
| spectralnorm | 1.00 | 10.13 | 1.05 | 106.66 | 1.05 | 0.97 | 2.32 | 6.42 |
| fannkuchredux | 1.00 | 3.58 | 0.80 | 19.64 | 0.30 | 0.76 | 0.88 | 2.57 |
| mandelbrot | 1.00 | 1.11 | 1.02 | 46.48 | 0.29 | 1.28 | 1.09 | 4.07 |
| fasta | 1.00 | 3.67 | 1.80 | 9.64 | 1.17 | 0.46 | 1.49 | 4.66 |
| knucleotide | 1.00 | 9.12 | 4.02 | 3.71 | N/A | N/A | N/A | N/A |
| revcomp | 1.00 | 57.22 | 8.31 | 8.94 | 1.48 | 12.95 | 1.48 | 17.66 |
| binarytrees | 1.00 | 16.51 | 4.53 | 7.02 | 0.15 | 4.61 | 0.99 | 1.53 |
| regexredux | 1.00 | 1.36 | 1.35 | 14.63 | 0.28 | 0.64 | 4.05 | 3.50 |
| pidigits | 1.00 | 1.04 | 1.00 | 11.19 | 1.51 | 1.05 | 2.51 | 10.88 |
| **Median** | **1.00** | **3.58** | **1.35** | **14.63** | **1.05** | **1.00** | **1.48** | **4.07** |
| **Arithmetic mean** | **1.00** | **10.73** | **2.43** | **33.38** | **0.90** | **2.64** | **1.76** | **5.95** |

## Source lines / Python

| Benchmark | C | idiomatic x2c | tuned x2c | Python | Rust | C++ | Go | Java |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| nbody | 1.38 | 1.15 | 1.15 | 1.00 | 1.49 | 1.55 | 1.37 | 1.54 |
| spectralnorm | 1.11 | 1.25 | 1.28 | 1.00 | 1.94 | 0.97 | 1.22 | 1.17 |
| fannkuchredux | 1.38 | 0.98 | 1.02 | 1.00 | 2.71 | 1.31 | 1.27 | 1.13 |
| mandelbrot | 1.34 | 0.91 | 0.94 | 1.00 | 4.56 | 0.78 | 1.59 | 1.34 |
| fasta | 1.84 | 0.87 | 1.00 | 1.00 | 0.81 | 1.76 | 1.79 | 2.02 |
| knucleotide | 0.87 | 0.28 | 0.34 | 1.00 | N/A | N/A | N/A | N/A |
| revcomp | 2.32 | 0.79 | 1.03 | 1.00 | 3.68 | 1.41 | 1.74 | 4.32 |
| binarytrees | 4.71 | 1.25 | 1.38 | 1.00 | 2.54 | 1.88 | 1.83 | 1.83 |
| regexredux | 3.24 | 1.03 | 1.32 | 1.00 | 1.46 | 8.11 | 1.97 | 1.49 |
| pidigits | 1.05 | 1.84 | 1.88 | 1.00 | 2.02 | 1.16 | 2.00 | 2.26 |
| **Median** | **1.38** | **1.03** | **1.15** | **1.00** | **2.02** | **1.41** | **1.74** | **1.54** |
| **Arithmetic mean** | **2.04** | **1.12** | **1.22** | **1.00** | **2.36** | **2.10** | **1.64** | **1.90** |


The median and the mean are orientation aids, not composite scores.
Read individual workloads; these summaries are not a language ranking.
