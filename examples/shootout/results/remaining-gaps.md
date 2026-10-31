# Remaining idiomatic x2c performance gaps

Current run `20261031T134323Z`, local profile, measured source
`d7c7787c7d1c608f86730b1ba5be3f22722c0299` on Apple M4 Max. Values are sixteen-sample median
elapsed milliseconds. These selected-program differences do not isolate
language, allocation, or threading overhead. Rows rank absolute excess over C.

| Workload | Idiomatic ms | C ms | Tuned ms | Idiomatic/C | Excess over C ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| knucleotide | 164.641 | 18.225 | 72.036 | 9.03 | 146.416 |
| binarytrees | 109.685 | 23.845 | 110.654 | 4.60 | 85.840 |
| spectralnorm | 72.368 | 7.105 | 7.346 | 10.19 | 65.263 |
| fannkuchredux | 55.580 | 15.044 | 12.067 | 3.69 | 40.537 |
| nbody | 60.950 | 30.934 | 62.403 | 1.97 | 30.017 |
| fasta | 29.272 | 8.043 | 14.466 | 3.64 | 21.229 |
| regexredux | 51.923 | 37.750 | 51.300 | 1.38 | 14.173 |
| pidigits | 268.183 | 256.630 | 255.558 | 1.05 | 11.553 |
| revcomp | 11.490 | 1.484 | 12.116 | 7.74 | 10.006 |
| mandelbrot | 9.899 | 8.910 | 8.995 | 1.11 | 0.988 |

## Completed source changes

The ordinary Node class and fused Buffer reverse-complement rewrite are now
implemented and validated. The Node class uses ordinary child fields and
allocates every leaf. The Buffer rewrite removes full-string reverse/upper/map
passes and generic per-byte callback dispatch, preserves IUPAC complements and
60-column wrapping, and handles blank sequence lines.

[This run's comparison](runs/20261031T134323Z/README.md) records before/after medians
alongside C drift. Full runs are separate observations, not alternating pairs.
The earlier n-body pair precomputation, FASTA Buffer reuse, and regex JIT remain
applied. No typed containers, SubStrings, raw storage, custom allocators, or
compiler/runtime changes were introduced by these two rewrites.

## Remaining candidates and limits

- **K-nucleotide:** short String keys, Map reads/writes, and numeric conversions
  need attribution. The obvious-looking `counts[key] += 1` substitution already
  regressed 20-21 percent and lost all twelve pairs at both tested sizes. Keep
  the existing counting loop. Generic dispatch is a hypothesis, not profiled
  attribution; the failed source substitution does not reject all Map work.
- **Spectral-norm and fannkuch-redux:** generic Array access and Var numeric
  conversion remain plausible costs. Typed containers are excluded from the
  idiomatic column. Profile ordinary operations before proposing shared-runtime
  or compiler specialization; no further compliant source fix is demonstrated.
- **Binary-trees:** C uses pthread workers, while the x2c entries remain serial.
  The ordinary Node representation gap to tuned x2c is addressed. Do not call
  the remaining C ratio pure allocation or language overhead. C++ supplies a
  useful serial comparison in the per-problem tables.
- **FASTA and reverse-complement:** ordinary per-line String/output and input
  handling remain candidates for profiling. The Buffer rewrite is not an
  in-place typed-storage implementation. Further gains are unmeasured.

The [paired-probe evidence](evidence/README.md) and older run archives retain
the original hypotheses, results, and rejected Map experiment. Current source
claims follow this latest run rather than silently rewriting older reports.
Java includes startup/JIT. Canonical-size timing remains unrun.
