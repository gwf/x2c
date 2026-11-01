# Remaining local performance gaps

Run `20261101T161913Z`, local profile, twelve fresh samples per x2c program. Foreign measurements remain pinned. Canonical-size comparisons remain unrun.

| Problem | Idiomatic ms | Tuned ms | Fastest selected | Tuned / fastest |
|---|---:|---:|---|---:|
| binarytrees | 26.300 | 27.093 | rust: 3.447 ms | 7.86x |
| regexredux | 25.262 | 25.843 | rust: 11.559 ms | 2.24x |
| knucleotide | 78.756 | 16.011 | c: 9.255 ms | 1.73x |
| mandelbrot | 4.684 | 4.039 | rust: 2.382 ms | 1.70x |
| fannkuchredux | 10.251 | 4.336 | cpp: 2.671 ms | 1.62x |
| spectralnorm | 17.890 | 6.420 | go: 4.285 ms | 1.50x |
| revcomp | 10.968 | 1.937 | c: 1.580 ms | 1.23x |
| nbody | 66.064 | 31.086 | cpp: 29.812 ms | 1.04x |
| fasta | 20.470 | 3.893 | c: 3.817 ms | 1.02x |
| pidigits | 268.702 | 257.019 | tuned: 257.019 ms | 1.00x |

The [accepted source comparisons](runs/20261101T161913Z/README.md) establish reverse-complement, FASTA and N-body gains against frozen prior binaries. Chunk reads and batched output reduce reverse-complement time and memory. FASTA replaces per-character collection growth and early-exit threshold selection. N-body removes generic iteration and allocated pair objects while preserving arithmetic order. No compiler or runtime changed.

Across eight shared workloads, tuned takes 1.24x C elapsed time and 1.06x Rust. Regex-redux is now the largest shared-program gap: counts already overlap the ordered substitution chain, and phase profiling is still needed before attributing the remaining cost. Mandelbrot/fannkuch scheduling and arithmetic kernels also remain candidates for measured investigation. Binary-trees retains the documented reference allocator differences and is excluded from the eight-way summary because Python is unavailable.

Only three tuned sources changed. Variations in unchanged programs between full runs are not evidence of source regressions. Twelve-pair final experiments, larger text inputs and 58 additional boundary cases preserve identical output. The prior archive retains threshold and rejected-candidate evidence from the threading campaign.

Use workload-matched ratios and geometric means. Dividing independently sorted column medians does not measure a typical same-workload slowdown.
