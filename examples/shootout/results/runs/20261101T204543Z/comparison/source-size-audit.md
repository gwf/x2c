# Source-size audit

Independent tokenization reproduces LOC and normalized gzip bytes for all 75 admitted sources, both at baseline `36c17924d` and on the final measured tree. No count defect was found.

LOC counts nonblank, noncomment physical source lines. Normalized gzip removes comments and collapses whitespace outside literals, then compresses at level 1. Imported libraries and generated output are excluded. Neither measure directly counts concepts or programmer effort.

| Workload | C LOC | Idiomatic LOC | Tuned LOC | C gzip bytes | Idiomatic gzip bytes | Tuned gzip bytes |
|---|---:|---:|---:|---:|---:|---:|
| nbody | 123 | 102 | 82 | 1166 | 1514 | 1348 |
| spectralnorm | 54 | 74 | 104 | 459 | 776 | 855 |
| fannkuchredux | 86 | 97 | 100 | 900 | 1006 | 1022 |
| mandelbrot | 69 | 55 | 56 | 774 | 751 | 777 |
| fasta | 131 | 65 | 82 | 1280 | 896 | 998 |
| knucleotide | 135 | 64 | 74 | 1484 | 771 | 889 |
| revcomp | 79 | 47 | 67 | 808 | 458 | 864 |
| binarytrees | 113 | 49 | 49 | 901 | 652 | 652 |
| regexredux | 120 | 61 | 97 | 1388 | 809 | 1288 |
| pidigits | 45 | 61 | 59 | 444 | 678 | 676 |

Across the eight shared problems, tuned uses 0.953x C LOC and 1.142x C gzip; idiomatic uses 0.822x C LOC and 0.979x C gzip. Thus C is smaller than tuned in compressed bytes, while x2c has fewer code lines overall.

Pidigits removes a private Integer forwarding layer and keeps the existing Spigot lifecycle. Idiomatic 79 -> 61 LOC, 900 -> 678 gzip bytes; tuned 81 -> 59 LOC, 917 -> 676 gzip bytes. The local paired timings are flat.

The faster tuned regex program adds an explicit scratch-buffer replacement helper, and that source cost remains in the chart. Spectral retains separately measured serial kernels; prior attempts to share the banded path regressed small inputs. Explicit Thread setup also costs more source than C OpenMP pragmas. These are concrete implementation tradeoffs, not reasons to remove behavior or compress physical lines.

See the adjacent compressed audit JSON for all 75 exact paths/hashes/counts and the tools directory for both independent audit scripts.
