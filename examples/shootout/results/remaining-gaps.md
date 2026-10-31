# Remaining idiomatic x2c performance gaps

These observations use quiet-window run `20261031T035446Z`, local profile,
measured source `68156a1c6`. Values are sixteen-sample median elapsed times
on Apple M4 Max. They describe selected programs and do not isolate language
or allocator overhead. The C implementation is the baseline in the ratio.

## Current measurements

Rows are ordered by absolute idiomatic x2c elapsed time minus C elapsed time.
A ratio alone can emphasize a tiny baseline rather than a large saved cost.

| Workload | Idiomatic ms | C ms | Tuned ms | Idiomatic/C | Excess over C ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| binarytrees | 401.320 | 24.308 | 110.059 | 16.51 | 377.012 |
| knucleotide | 168.186 | 18.445 | 74.090 | 9.12 | 149.741 |
| revcomp | 85.082 | 1.487 | 12.361 | 57.22 | 83.596 |
| spectralnorm | 75.737 | 7.476 | 7.858 | 10.13 | 68.261 |
| fannkuchredux | 56.369 | 15.738 | 12.564 | 3.58 | 40.631 |
| nbody | 66.003 | 33.507 | 66.120 | 1.97 | 32.496 |
| fasta | 29.779 | 8.104 | 14.581 | 3.67 | 21.675 |
| regexredux | 52.966 | 38.888 | 52.675 | 1.36 | 14.077 |
| pidigits | 272.224 | 260.734 | 261.049 | 1.04 | 11.490 |
| mandelbrot | 9.909 | 8.935 | 9.110 | 1.11 | 0.974 |

## Strongest remaining source opportunities

**Binary-trees: use the existing ordinary Node class.** The idiomatic entry
represents every tree node as a two-element Array. The tuned entry already
uses `class Node { Node left, right; } *`, ordinary allocation, and the same
Scope regions. That entry uses no typed container, SubString, raw collection
storage, or custom allocator. An ordinary heap class belongs within the
stated idiomatic policy; the two columns need not differ artificially.
Its observed 110.059 ms versus the Array version's 401.320 ms makes this the
strongest existing source alternative to validate for idiomatic adoption.
This comparison identifies an available implementation, not an isolated
allocation-cost measurement. Every leaf must remain allocated as required.

The C binary-trees contribution launches pthread workers. Tuned x2c and the
serial C++ contribution are approximately 110 ms in this run, while C is
24.308 ms. Do not interpret the remaining C ratio as pure x2c allocation
cost. Separate representation and parallelism when measuring a future change.
Sources: [idiomatic](../benchmarks/binarytrees/main.x),
[tuned](../benchmarks/binarytrees/tuned.x), and
[C](../benchmarks/binarytrees/main.c).

**Reverse-complement: fuse the existing string passes through ordinary
Buffer APIs.** The current entry creates a reversed String, uppercases it,
then calls a generic byte callback through `String.map`. Its complement
function linearly searches a 16-character alphabet for every byte. The
String implementation confirms one `Func.apply_value` call per byte.
A reverse traversal that folds case, complements, and writes to an ordinary
Buffer could remove intermediate full strings and generic callbacks.
Preserve all IUPAC complements, lowercase handling, record boundaries, and
60-column output. This Buffer candidate has not been implemented or timed;
the tuned entry's 12.361 ms also benefits from typed storage and raw output,
so its entire advantage cannot be credited to pass fusion.
Sources: [idiomatic](../benchmarks/revcomp/main.x),
[tuned](../benchmarks/revcomp/tuned.x), and
[String.map](../../../lib/string/mapping.x).

## Gaps that need attribution before a fix

- **K-nucleotide:** repeated short String keys, Map reads/writes, and numeric
  conversions are plausible costs. The obvious-looking additive update was
  tested and lost: `counts[key] += 1` took 214.105 ms versus 178.407 ms in
  the paired local probe, and 998.393 versus 824.380 ms at five times the
  input. It lost all twelve pairs at both sizes. Keep the current counting
  loop. Generic numeric dispatch is a source-based hypothesis for that
  regression, not profiled attribution. Investigate the actual key/hash/update
  costs before changing shared Map/runtime behavior.
- **Spectral-norm:** the inner quadratic loops repeatedly read generic Array
  elements and convert Var values to double. The existing typed variant
  demonstrates a large alternative implementation gap, but typed containers
  are excluded from the idiomatic column. Profile ordinary Array access and
  conversion before proposing compiler/runtime specialization. No obvious
  compliant source substitution has been demonstrated.
- **Fannkuch-redux:** generic Array indexing, swaps, rotations, and numeric
  conversion dominate source-level differences from the typed variant.
  Investigate reusable ordinary collection operations and generated calls;
  do not silently move typed arrays or raw storage into the idiomatic entry.
- **FASTA:** Buffer reuse is already applied. Per-character writes, cumulative
  probability lookup through ordinary Arrays, and per-line String/output work
  remain. Further gains are candidates, not established fixes.

## Already applied and measured

The three accepted source changes were published at `68156a1c6`: n-body
pair precomputation, FASTA Buffer reuse, and regex JIT. The latest full rerun
records n-body at 66.003 ms and regex-redux at 52.966 ms, approximately the
same as their tuned entries (66.120 ms and 52.675 ms). Those two gaps to the
tuned column are substantially closed on the local workloads.

The [archived comparison](runs/20261031T035446Z/charts/README.md) shows the
previous and latest medians with C drift. Those are separate full runs.
The [paired-probe evidence](evidence/README.md) separately retains alternating
baseline/variant measurements at two sizes, plus the rejected Map experiment.
Do not combine their percentages or treat the larger probe sizes as canonical.

No further source fix is applied by this documentation change. Next, validate
ordinary Node adoption, then test the Buffer reverse-complement candidate.
Runtime/compiler changes require evidence and their existing design boundaries.
Canonical-size timing remains unrun.
