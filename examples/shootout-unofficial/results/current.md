# x2c language shootout result

- Run: `20260906T205905Z`
- Baseline: `566683b7bee6bdee`
- Profile: `local`
- Samples: 12 fresh-process x2c measurements after 1 warmup(s)
- `x2c` is each benchmark's `main.x`, which writes the problem in x2c.
  `ported` is its `ported.x`, which keeps the C representation and uses
  x2c only where the C was verbose.
- Time uses C as the implicit 1.00 baseline; SLOC uses Python as the
  implicit 1.00 baseline. Larger values mean more cost.

| Benchmark | Time x2c/C | Time ported/C | Time Python/C | SLOC x2c/Python | SLOC ported/Python | SLOC C/Python |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| nbody | 0.95 | 0.95 | 125.24 | 1.11 | 1.15 | 1.43 |
| spectralnorm | 0.95 | 0.93 | 110.56 | 1.69 | 1.69 | 1.65 |
| fannkuchredux | 0.76 | 0.74 | 20.13 | 1.29 | 1.46 | 1.74 |
| binarytrees | 2.28 | 0.94 | 3.84 | 1.53 | 1.65 | 2.53 |
| brainfuck | 0.97 | 0.97 | 57.75 | 1.29 | 1.33 | 1.60 |
| wordfreq | 5.22 | 0.99 | 8.22 | 1.60 | 2.80 | 3.24 |
| mandelbrot | 1.01 | 0.99 | 136.17 | 1.27 | 1.27 | 1.50 |
| sieve | 1.05 | 1.03 | 20.13 | 1.93 | 1.80 | 1.87 |
| matmul | 1.02 | 1.00 | 87.73 | 1.73 | 1.93 | 2.00 |
| gameoflife | 1.07 | 0.98 | 340.56 | 1.52 | 1.43 | 1.38 |
| quicksort | 1.02 | 1.03 | 16.41 | 1.20 | 1.13 | 1.13 |
| graphbfs | 1.23 | 2.70 | 3.20 | 1.69 | 1.59 | 1.69 |
| calculatorast | 11.00 | 0.98 | 77.36 | 1.30 | 2.13 | 1.87 |
| csvparse | 2.00 | 1.00 | 4.70 | 2.53 | 2.65 | 2.71 |
| **Median** | **1.04** | **0.99** | **38.94** | **1.53** | **1.62** | **1.72** |
| **Arithmetic mean** | **2.18** | **1.09** | **72.29** | **1.55** | **1.71** | **1.88** |

The median and the mean are orientation aids, not composite scores.
One benchmark dominates the mean, so the median is the more useful
of the two; read the per-benchmark rows for anything that matters.
