# x2c Benchmarks Game result

- Run: `20261031T161720Z`
- Baseline: `3a798f74363417e9`
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
| nbody | 1.00 | 2.00 | 2.00 | 79.34 | 1.94 | 1.00 | 1.01 | 2.24 |
| spectralnorm | 1.00 | 2.46 | 1.04 | 110.77 | 1.08 | 0.94 | 2.33 | 6.56 |
| fannkuchredux | 1.00 | 3.15 | 0.80 | 20.07 | 0.30 | 0.76 | 0.87 | 2.55 |
| mandelbrot | 1.00 | 1.11 | 1.01 | 46.22 | 0.27 | 1.28 | 1.08 | 4.07 |
| fasta | 1.00 | 2.49 | 1.85 | 9.94 | 1.20 | 0.47 | 1.52 | 4.87 |
| knucleotide | 1.00 | 9.13 | 3.99 | 3.64 | N/A | N/A | N/A | N/A |
| revcomp | 1.00 | 7.73 | 8.16 | 8.73 | 1.44 | 12.64 | 1.46 | 17.75 |
| binarytrees | 1.00 | 1.16 | 1.14 | 7.07 | 0.16 | 4.53 | 0.99 | 1.56 |
| regexredux | 1.00 | 1.38 | 1.36 | 14.70 | 0.29 | 0.63 | 4.18 | 3.56 |
| pidigits | 1.00 | 1.05 | 1.00 | 11.36 | 1.58 | 1.05 | 2.67 | 11.00 |
| **Median** | **1.00** | **2.00** | **1.14** | **14.70** | **1.08** | **1.00** | **1.46** | **4.07** |
| **Arithmetic mean** | **1.00** | **2.50** | **2.04** | **34.24** | **0.92** | **2.59** | **1.79** | **6.02** |

## Source lines / Python

| Benchmark | C | idiomatic x2c | tuned x2c | Python | Rust | C++ | Go | Java |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| nbody | 1.38 | 1.15 | 1.15 | 1.00 | 1.49 | 1.55 | 1.37 | 1.54 |
| spectralnorm | 1.11 | 2.06 | 1.28 | 1.00 | 1.94 | 0.97 | 1.22 | 1.17 |
| fannkuchredux | 1.38 | 0.98 | 1.02 | 1.00 | 2.71 | 1.31 | 1.27 | 1.13 |
| mandelbrot | 1.34 | 0.91 | 0.94 | 1.00 | 4.56 | 0.78 | 1.59 | 1.34 |
| fasta | 1.84 | 1.05 | 1.00 | 1.00 | 0.81 | 1.76 | 1.79 | 2.02 |
| knucleotide | 0.87 | 0.28 | 0.34 | 1.00 | N/A | N/A | N/A | N/A |
| revcomp | 2.32 | 1.38 | 1.03 | 1.00 | 3.68 | 1.41 | 1.74 | 4.32 |
| binarytrees | 4.71 | 2.04 | 2.04 | 1.00 | 2.54 | 1.88 | 1.83 | 1.83 |
| regexredux | 3.24 | 1.03 | 1.32 | 1.00 | 1.46 | 8.11 | 1.97 | 1.49 |
| pidigits | 1.05 | 1.84 | 1.88 | 1.00 | 2.02 | 1.16 | 2.00 | 2.26 |
| **Median** | **1.38** | **1.15** | **1.15** | **1.00** | **2.02** | **1.41** | **1.74** | **1.54** |
| **Arithmetic mean** | **2.04** | **1.38** | **1.30** | **1.00** | **2.36** | **2.10** | **1.64** | **1.90** |


The median and the mean are orientation aids, not composite scores.
Read individual workloads; these summaries are not a language ranking.
