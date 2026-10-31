# Remaining local performance gaps

Run `20261031T211435Z`, clean source `3318f8d8aea057e95b9a9dbf1ccc09d8e7a36d4a`, local profile, 56 samples per program.
These are selected-program measurements, not general language overhead.
Canonical-size timing remains unrun. Eight problems share every column;
k-nucleotide and binary-trees remain available in per-problem rows.

| Problem | Idiomatic ms | C ms | Tuned ms | Fastest selected ms | Idiomatic / fastest |
| --- | ---: | ---: | ---: | --- | ---: |
| knucleotide | 90.158 | 9.255 | 75.645 | c: 9.255 | 9.74 |
| binarytrees | 26.731 | 24.571 | 26.409 | rust: 3.447 | 7.75 |
| revcomp | 11.618 | 1.580 | 12.857 | c: 1.580 | 7.35 |
| fasta | 21.084 | 3.817 | 15.114 | c: 3.817 | 5.52 |
| spectralnorm | 17.689 | 4.995 | 8.099 | go: 4.285 | 4.13 |
| fannkuchredux | 9.908 | 3.419 | 13.176 | cpp: 2.671 | 3.71 |
| nbody | 67.953 | 32.841 | 68.064 | cpp: 29.812 | 2.28 |
| regexredux | 26.100 | 12.218 | 55.446 | rust: 11.559 | 2.26 |
| mandelbrot | 4.457 | 2.835 | 9.986 | rust: 2.382 | 1.87 |
| pidigits | 275.527 | 263.393 | 262.694 | tuned: 262.694 | 1.05 |

The controlled local source comparisons are:

| Experiment | Input N | Before elapsed ms | Candidate elapsed ms | Before CPU ms | Candidate CPU ms | Paired wins / 12 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| regexredux | 100000 | 50.900 | 24.202 | 50.547 | 56.156 | 12 |
| revcomp | 100000 | 11.654 | 10.958 | 11.306 | 10.670 | 12 |
| mandelbrot | 512 | 9.899 | 4.369 | 9.591 | 12.153 | 12 |

All three changes win every paired local round and also benefit larger inputs.
Parallelism spends more total CPU for lower elapsed time; the Buffer change
reduces both metrics. Full-run differences in unchanged programs are not gains
caused by these source changes. All 55 foreign source bytes, workload profiles
and compiler/runtime source are unchanged from the source-probe baseline unless
a separately recorded upstream integration says otherwise.

K-nucleotide still spends substantial time in canonical String slicing/interning
and Map work. Counter objects and compound Map updates did not help in earlier
probes; ordinary width-level threading did. Binary-trees is close to C, while
fast library-arena Rust references remain much faster; a specialized allocator
is outside the idiomatic boundary. The remaining reverse-complement cost needs
further profiling before another rewrite. FASTA Choice-record probes did not
establish a gain; that rejects the tested source, not every record-based design.

No additional compiler/runtime redesign is implied by these benchmark gaps.
See [recovery](README.md), [threading](threading.md), and the latest run's
focused experiment and raw receipts.
