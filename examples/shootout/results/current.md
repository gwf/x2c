# x2c language shootout result

- Run: `20260809T011300Z`
- Baseline: `1e0e7fd78d7ad071`
- Profile: `local`
- Samples: 12 fresh-process x2c measurements after 1 warmup(s)
- `x2c` is each benchmark's `main.x`, which writes the problem in x2c.
  `ported` is its `ported.x`, which keeps the C representation and uses
  x2c only where the C was verbose.
- Time uses C as the implicit 1.00 baseline; SLOC uses Python as the
  implicit 1.00 baseline. Larger values mean more cost.

| Benchmark | Time x2c/C | Time ported/C | Time Python/C | SLOC x2c/Python | SLOC ported/Python | SLOC C/Python |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| nbody | 1.00 | 0.99 | 125.18 | 1.11 | 1.15 | 1.43 |
| spectralnorm | 0.98 | 0.96 | 108.79 | 1.69 | 1.69 | 1.65 |
| fannkuchredux | 0.81 | 0.79 | 20.29 | 1.29 | 1.46 | 1.74 |
| binarytrees | 7.19 | 1.21 | 7.59 | 1.71 | 1.65 | 2.53 |
| brainfuck | 1.02 | 1.01 | 55.47 | 1.29 | 1.33 | 1.60 |
| wordfreq | 5.08 | 1.02 | 7.99 | 1.68 | 2.84 | 3.24 |
| mandelbrot | 1.00 | 1.00 | 125.76 | 1.27 | 1.27 | 1.50 |
| sieve | 1.01 | 1.00 | 18.16 | 1.93 | 1.80 | 1.87 |
| matmul | 1.07 | 1.04 | 83.26 | 1.73 | 1.93 | 2.00 |
| gameoflife | 1.07 | 0.99 | 320.05 | 1.57 | 1.43 | 1.38 |
| quicksort | 0.98 | 1.00 | 15.48 | 1.20 | 1.13 | 1.13 |
| graphbfs | 0.90 | 1.71 | 2.96 | 1.69 | 1.59 | 1.69 |
| calculatorast | 46.91 | 0.93 | 70.09 | 1.33 | 2.17 | 1.87 |
| csvparse | 6.83 | 1.03 | 4.70 | 2.47 | 2.65 | 2.71 |
| **Median** | **1.02** | **1.00** | **37.88** | **1.63** | **1.62** | **1.72** |
| **Arithmetic mean** | **5.42** | **1.05** | **68.98** | **1.57** | **1.72** | **1.88** |

The median and the mean are orientation aids, not composite scores.
One benchmark dominates the mean, so the median is the more useful
of the two; read the per-benchmark rows for anything that matters.
