# Remaining local performance gaps

Run `20261101T204543Z`, local profile, twelve fresh samples per x2c program. Foreign measurements remain pinned. Canonical-size comparisons remain unrun.

| Problem | Idiomatic ms | Tuned ms | Fastest selected | Tuned / fastest |
|---|---:|---:|---|---:|
| binarytrees | 26.751 | 26.490 | rust: 3.447 ms | 7.68x |
| knucleotide | 84.198 | 16.236 | c: 9.255 ms | 1.75x |
| mandelbrot | 4.342 | 3.760 | rust: 2.382 ms | 1.58x |
| spectralnorm | 17.631 | 6.152 | go: 4.285 ms | 1.44x |
| fannkuchredux | 9.829 | 3.767 | cpp: 2.671 ms | 1.41x |
| revcomp | 11.342 | 2.026 | c: 1.580 ms | 1.28x |
| regexredux | 25.160 | 12.320 | rust: 11.559 ms | 1.07x |
| nbody | 71.296 | 31.501 | cpp: 29.812 ms | 1.06x |
| fasta | 20.597 | 3.976 | c: 3.817 ms | 1.04x |
| pidigits | 272.308 | 260.170 | tuned: 260.170 ms | 1.00x |

The [regex phase investigation and source comparisons](runs/20261101T204543Z/README.md) establish a roughly twofold tuned regex gain. Repeated sizing scans and String canonicalization dominated the former replacement path. A specialized literal helper now alternates typed scratch buffers; worker counts already overlap that serial chain. No general PCRE2 API change was adopted.

Across eight shared workloads, tuned takes 1.11x C elapsed time and 0.95x Rust. K-nucleotide, Mandelbrot and fannkuch retain larger gaps to selected references. Binary-trees retains documented allocator differences and is excluded from the eight-way summary because Python is unavailable. These are candidates for investigation, not established runtime defects.

Pidigits removes its private Integer forwarding layer with flat local elapsed time. Independent audits reproduce all 75 old and new source-size counts. Spectral retains its measured serial specialization rather than accepting the earlier slower shared kernel. Unchanged-program timing differences between full runs are not attributed to source changes.

Final source comparisons use one integrated compiler/runtime and alternating fresh processes, with raw CPU/RSS records and monitored quiet windows. Foreign timings remain pinned. Use matched workload ratios and geometric means; ratios of independently sorted column medians are not typical same-workload slowdowns.
