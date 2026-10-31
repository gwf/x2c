# Remaining idiomatic x2c performance gaps

Current run `20261031T170749Z`, local profile, measured source
`06a81d6535120d6c0c07e320751548075c5d3fc1` on Apple M4 Max. Values are sixteen-sample median
elapsed milliseconds. Selected-program differences do not isolate language,
allocation, or threading overhead. Rows rank absolute excess over C; negative
excess means the selected x2c program ran faster than the selected C program.

| Workload | Idiomatic ms | C ms | Tuned ms | Idiomatic/C | Excess over C ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| knucleotide | 170.790 | 18.918 | 75.638 | 9.03 | 151.872 |
| nbody | 67.616 | 32.858 | 68.606 | 2.06 | 34.758 |
| regexredux | 54.524 | 39.759 | 54.306 | 1.37 | 14.766 |
| fasta | 21.609 | 8.735 | 15.451 | 2.47 | 12.873 |
| pidigits | 273.683 | 262.181 | 260.864 | 1.04 | 11.501 |
| revcomp | 12.249 | 1.539 | 12.724 | 7.96 | 10.710 |
| spectralnorm | 17.996 | 7.847 | 8.164 | 2.29 | 10.150 |
| binarytrees | 27.602 | 24.832 | 26.805 | 1.11 | 2.770 |
| mandelbrot | 11.137 | 9.984 | 10.182 | 1.12 | 1.153 |
| fannkuchredux | 10.025 | 16.337 | 13.184 | 0.61 | -6.313 |

## Latest experiments

Parallel fannkuch: **adopted**. Cached k-nucleotide loop bound: **adopted**.
[Run 20261031T170749Z](runs/20261031T170749Z/README.md) preserves the exact decisions, paired elapsed
and CPU measurements, full-run C drift, candidate sources, and correctness
checks. The earlier serial fannkuch source and all prior charts remain intact.
No typed containers, raw collection storage, custom allocators, or runtime or
compiler changes were introduced by these benchmark changes.

Counter objects and `counts[key] += 1` remain rejected k-nucleotide experiments.
Their failure does not rule out all Map or representation improvements.
K-nucleotide slicing, canonical String storage, hashing, and value conversions
still need profiling. N-body has no further demonstrated idiomatic source fix.
A regex count-only API is a possible adapter improvement, not an implemented
benchmark change. Parallel strategies affect elapsed time and CPU consumption;
these comparisons do not establish single-core language performance.

Earlier Node, Buffer, pair precomputation, bulk copy, Choice records, regex JIT,
and parallel tree/spectral changes remain applied. Java includes startup/JIT.
Canonical-size timing remains unrun.
