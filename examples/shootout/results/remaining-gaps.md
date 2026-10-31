# Remaining idiomatic x2c performance gaps

Current run `20261031T145604Z`, local profile, measured source
`e44721497e0004c921ccacec098f330bd2248726` on Apple M4 Max. Values are sixteen-sample median
elapsed milliseconds. These selected-program differences do not isolate
language, allocation, or threading overhead. Rows rank absolute excess over C.

| Workload | Idiomatic ms | C ms | Tuned ms | Idiomatic/C | Excess over C ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| knucleotide | 171.022 | 18.846 | 74.325 | 9.07 | 152.175 |
| spectralnorm | 74.236 | 7.119 | 7.226 | 10.43 | 67.116 |
| nbody | 65.880 | 32.017 | 68.598 | 2.06 | 33.863 |
| fannkuchredux | 48.507 | 15.397 | 12.439 | 3.15 | 33.110 |
| regexredux | 53.862 | 39.199 | 53.594 | 1.37 | 14.662 |
| fasta | 20.625 | 8.244 | 14.981 | 2.50 | 12.380 |
| pidigits | 274.598 | 263.617 | 261.645 | 1.04 | 10.982 |
| revcomp | 11.960 | 1.567 | 12.512 | 7.63 | 10.393 |
| binarytrees | 25.650 | 23.824 | 26.303 | 1.08 | 1.825 |
| mandelbrot | 9.871 | 8.929 | 8.990 | 1.11 | 0.942 |

## Completed source changes

Fannkuch now copies into its existing working Array with `setslice`. FASTA
precomputes an Array of ordinary Choice objects, then reads their fields during
sampling. The cumulative probabilities and random-number steps are unchanged.
The earlier ordinary Node, reverse-complement Buffer, n-body pair, FASTA Buffer,
and regex JIT changes remain applied. Binary-trees now uses one ordinary Thread
per depth batch in both columns.
The serial source and same-compiler quiet elapsed/CPU comparison are retained.
No typed containers, SubStrings, raw storage, custom allocators, or
compiler/runtime changes were introduced.

[This run's comparison](runs/20261031T145604Z/README.md) records before/after medians
alongside C drift. Full runs are separate observations, not alternating pairs.
The saved [probe evidence](evidence/README.md) records the paired experiments.

## Remaining candidates and limits

- **K-nucleotide:** short String keys, Map reads/writes, and numeric conversions
  need attribution. The obvious-looking `counts[key] += 1` substitution already
  regressed 20-21 percent and lost all twelve pairs at both tested sizes. Keep
  the existing counting loop. Generic dispatch is a hypothesis, not profiled
  attribution; the failed source substitution does not reject all Map work.
- **Spectral-norm and fannkuch-redux:** generic Array access and Var numeric
  conversion remain plausible costs after the fannkuch copy improvement.
  Typed containers are excluded from the idiomatic column. Profile ordinary
  operations before proposing runtime or compiler specialization.
- **Binary-trees:** C and both x2c entries use one worker per depth batch.
  The ordinary Node representation gap to tuned x2c is addressed. The remaining
  C ratio is not pure allocation or language overhead. The serial source and
  elapsed/CPU comparison remain archived; see [threading](threading.md).
- **FASTA and reverse-complement:** allocation, generic operations, and input/output
  handling remain profiling candidates. The validated records and Buffer work
  does not demonstrate another compliant source fix.

Original hypotheses, older results, and the rejected Map experiment remain in
the immutable archives. Java includes startup/JIT. Canonical-size timing is unrun.
