# x2c Benchmarks Game result

- Run: `20261031T145604Z`
- Baseline: `7aa3e0e370d3129b`
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
| nbody | 1.00 | 2.06 | 2.14 | 79.01 | 1.92 | 0.99 | 1.00 | 2.21 |
| spectralnorm | 1.00 | 10.43 | 1.02 | 110.91 | 1.08 | 0.94 | 2.32 | 6.49 |
| fannkuchredux | 1.00 | 3.15 | 0.81 | 20.09 | 0.30 | 0.76 | 0.86 | 2.54 |
| mandelbrot | 1.00 | 1.11 | 1.01 | 46.43 | 0.28 | 1.29 | 1.08 | 4.06 |
| fasta | 1.00 | 2.50 | 1.82 | 9.78 | 1.20 | 0.47 | 1.52 | 4.89 |
| knucleotide | 1.00 | 9.07 | 3.94 | 3.80 | N/A | N/A | N/A | N/A |
| revcomp | 1.00 | 7.63 | 7.98 | 8.65 | 1.43 | 12.43 | 1.48 | 17.58 |
| binarytrees | 1.00 | 1.08 | 1.10 | 7.19 | 0.16 | 4.59 | 1.01 | 1.61 |
| regexredux | 1.00 | 1.37 | 1.37 | 14.80 | 0.29 | 0.63 | 4.03 | 3.52 |
| pidigits | 1.00 | 1.04 | 0.99 | 11.14 | 1.50 | 1.04 | 2.51 | 10.83 |
| **Median** | **1.00** | **2.06** | **1.10** | **14.80** | **1.08** | **0.99** | **1.48** | **4.06** |
| **Arithmetic mean** | **1.00** | **3.37** | **2.03** | **34.22** | **0.91** | **2.57** | **1.76** | **5.97** |

## Source lines / Python

| Benchmark | C | idiomatic x2c | tuned x2c | Python | Rust | C++ | Go | Java |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| nbody | 1.38 | 1.15 | 1.15 | 1.00 | 1.49 | 1.55 | 1.37 | 1.54 |
| spectralnorm | 1.11 | 1.25 | 1.28 | 1.00 | 1.94 | 0.97 | 1.22 | 1.17 |
| fannkuchredux | 1.38 | 0.98 | 1.02 | 1.00 | 2.71 | 1.31 | 1.27 | 1.13 |
| mandelbrot | 1.34 | 0.91 | 0.94 | 1.00 | 4.56 | 0.78 | 1.59 | 1.34 |
| fasta | 1.84 | 1.05 | 1.00 | 1.00 | 0.81 | 1.76 | 1.79 | 2.02 |
| knucleotide | 0.87 | 0.28 | 0.34 | 1.00 | N/A | N/A | N/A | N/A |
| revcomp | 2.32 | 1.38 | 1.03 | 1.00 | 3.68 | 1.41 | 1.74 | 4.32 |
| binarytrees | 4.71 | 2.04 | 2.04 | 1.00 | 2.54 | 1.88 | 1.83 | 1.83 |
| regexredux | 3.24 | 1.03 | 1.32 | 1.00 | 1.46 | 8.11 | 1.97 | 1.49 |
| pidigits | 1.05 | 1.84 | 1.88 | 1.00 | 2.02 | 1.16 | 2.00 | 2.26 |
| **Median** | **1.38** | **1.15** | **1.15** | **1.00** | **2.02** | **1.41** | **1.74** | **1.54** |
| **Arithmetic mean** | **2.04** | **1.29** | **1.30** | **1.00** | **2.36** | **2.10** | **1.64** | **1.90** |


The median and the mean are orientation aids, not composite scores.
Read individual workloads; these summaries are not a language ranking.
