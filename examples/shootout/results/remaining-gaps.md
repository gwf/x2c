# Remaining local performance gaps

Run `20261101T154144Z`, local profile, twelve fresh samples per x2c program. Foreign measurements remain pinned to the prior calibration. These are complete-program results; canonical-size timings remain unrun.

| Problem | Idiomatic ms | Tuned ms | Fastest selected | Tuned / fastest |
|---|---:|---:|---|---:|
| binarytrees | 25.312 | 25.861 | rust: 3.447 ms | 7.50x |
| revcomp | 11.644 | 5.930 | c: 1.580 ms | 3.75x |
| fasta | 19.770 | 14.281 | c: 3.817 ms | 3.74x |
| nbody | 70.317 | 67.324 | cpp: 29.812 ms | 2.26x |
| regexredux | 24.550 | 24.586 | rust: 11.559 ms | 2.13x |
| knucleotide | 90.761 | 16.168 | c: 9.255 ms | 1.75x |
| mandelbrot | 4.282 | 3.703 | rust: 2.382 ms | 1.55x |
| spectralnorm | 17.582 | 6.105 | go: 4.285 ms | 1.42x |
| fannkuchredux | 9.718 | 3.616 | cpp: 2.671 ms | 1.35x |
| pidigits | 266.781 | 258.184 | tuned: 258.184 ms | 1.00x |

The [source-parity comparisons](runs/20261101T154144Z/README.md) establish large gains in all six changed tuned programs at local and larger inputs. Spectral remains serial below500 to avoid measured startup costs, and fannkuch retains native element copying after bulk setslice lost on small inputs. Foreign source bytes and workload profiles remain unchanged.

The remaining gaps require program-specific profiling. Reverse-complement and FASTA still include ordinary canonical input handling; regex elapsed time includes the ordered substitution chain even when counts overlap. N-body was unchanged. The fast tree references retain their documented allocator differences. These observations do not establish a compiler/runtime defect or authorize another redesign.

Compare workload-matched ratios when summarizing idiomatic versus tuned. The median of each independently sorted C-normalized column is an orientation aid; dividing those two medians is not the median same-workload slowdown.
