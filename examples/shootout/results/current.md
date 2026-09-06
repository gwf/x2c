# x2c language shootout result

- Run: `20260906T191455Z`
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
| nbody | 1.02 | 1.02 | 125.24 | 1.11 | 1.15 | 1.43 |
| spectralnorm | 1.00 | 0.98 | 110.56 | 1.69 | 1.69 | 1.65 |
| fannkuchredux | 0.81 | 0.79 | 20.13 | 1.29 | 1.46 | 1.74 |
| binarytrees | 3.89 | 0.96 | 3.84 | 1.71 | 1.65 | 2.53 |
| brainfuck | 0.95 | 0.96 | 57.75 | 1.29 | 1.33 | 1.60 |
| wordfreq | 5.36 | 0.94 | 8.22 | 1.60 | 2.80 | 3.24 |
| mandelbrot | 1.00 | 0.99 | 136.17 | 1.27 | 1.27 | 1.50 |
| sieve | 0.98 | 0.99 | 20.13 | 1.93 | 1.80 | 1.87 |
| matmul | 1.03 | 1.00 | 87.73 | 1.73 | 1.93 | 2.00 |
| gameoflife | 1.09 | 1.00 | 340.56 | 1.52 | 1.43 | 1.38 |
| quicksort | 1.01 | 1.03 | 16.41 | 1.20 | 1.13 | 1.13 |
| graphbfs | 0.92 | 1.69 | 3.20 | 1.69 | 1.59 | 1.69 |
| calculatorast | 11.56 | 0.99 | 77.36 | 1.30 | 2.13 | 1.87 |
| csvparse | 7.32 | 1.05 | 4.70 | 2.76 | 2.65 | 2.71 |
| **Median** | **1.01** | **0.99** | **38.94** | **1.56** | **1.62** | **1.72** |
| **Arithmetic mean** | **2.71** | **1.03** | **72.29** | **1.58** | **1.71** | **1.88** |

The median and the mean are orientation aids, not composite scores.
One benchmark dominates the mean, so the median is the more useful
of the two; read the per-benchmark rows for anything that matters.
