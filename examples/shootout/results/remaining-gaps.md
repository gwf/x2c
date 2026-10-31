# Remaining local performance gaps

Run `20261031T181939Z`, clean measured source `381673a8d6d51098a44f62a635db98c0c9ca927e`, local profile, 56 samples
per program. These are measured programs, not general language overhead.
Canonical-size timing remains unrun. All eight shared problems use the same
cohort; k-nucleotide and binary-trees stay in per-problem rows.

| Problem | Idiomatic ms | C ms | Tuned ms | Fastest selected ms | Idiomatic / fastest |
| --- | ---: | ---: | ---: | --- | ---: |
| knucleotide | 86.195 | 8.960 | 74.474 | c: 8.960 | 9.62 |
| binarytrees | 26.277 | 24.384 | 26.077 | rust: 3.249 | 8.09 |
| revcomp | 11.925 | 1.486 | 12.582 | c: 1.486 | 8.03 |
| fasta | 20.769 | 3.658 | 14.815 | c: 3.658 | 5.68 |
| regexredux | 54.444 | 11.887 | 53.784 | rust: 11.184 | 4.87 |
| mandelbrot | 10.450 | 2.697 | 9.353 | rust: 2.286 | 4.57 |
| spectralnorm | 17.533 | 4.985 | 7.787 | go: 4.067 | 4.31 |
| fannkuchredux | 9.835 | 3.287 | 12.979 | cpp: 2.531 | 3.89 |
| nbody | 65.031 | 31.857 | 65.884 | cpp: 28.916 | 2.25 |
| pidigits | 271.954 | 261.074 | 259.861 | tuned: 259.861 | 1.05 |

The reference audit changes many baselines. A larger x2c/C ratio can result
from a faster adopted C program even when x2c is unchanged. Compare absolute
milliseconds and source identities before attributing changes. Earlier aggregate
summaries have nine shared problems; the current summaries have eight.

K-nucleotide profiling finds String slicing/intern-pool lookup and Map work.
Seven ordinary Threads cut the controlled local median from 163.604 ms to 83.901 ms
(all 8 paired rounds faster). Every width still builds a full growing Map.
Counter objects, compound Map assignment and earlier attempted shortcuts remain
rejected in preserved evidence. Typed Substr maps remain a tuned-only option.
Further shared-pool runtime changes need a separate design decision, because
allocation, lifetime and synchronization affect more than this benchmark.

Ordinary Thread batches for regex-redux pattern counts and independent
reverse-complement records may merit later probes. Official C submissions
provide parallel precedent. Library pools explain part of the fast tree
reference results, but adopting a specialized allocator is outside the
idiomatic definition. These findings do not authorize a runtime redesign. That is a candidate, not a
measured win from this task. Reference audit, k-nucleotide profiling/threading,
validation, quiet full rerun and charts are this batch's completed scope.
Source-specific raw C, typed storage or custom allocation is not an idiomatic fix.

See [run evidence](runs/20261031T181939Z/README.md),
[reference coverage](reference-coverage.md) and [threading](threading.md).
