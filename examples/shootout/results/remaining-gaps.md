# Remaining idiomatic x2c performance gaps

Current run `20261031T161720Z`, local profile, measured source
`a8d02959e25f6517cdcf189d386c637f587f016e` on Apple M4 Max. Values are sixteen-sample median
elapsed milliseconds. These selected-program differences do not isolate
language, allocation, or threading overhead. Rows rank absolute excess over C.

| Workload | Idiomatic ms | C ms | Tuned ms | Idiomatic/C | Excess over C ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| knucleotide | 168.942 | 18.502 | 73.807 | 9.13 | 150.440 |
| fannkuchredux | 48.416 | 15.377 | 12.256 | 3.15 | 33.038 |
| nbody | 63.562 | 31.775 | 63.533 | 2.00 | 31.788 |
| regexredux | 53.411 | 38.725 | 52.833 | 1.38 | 14.686 |
| pidigits | 278.149 | 266.141 | 265.173 | 1.05 | 12.008 |
| fasta | 19.767 | 7.944 | 14.665 | 2.49 | 11.823 |
| spectralnorm | 17.591 | 7.139 | 7.393 | 2.46 | 10.452 |
| revcomp | 11.813 | 1.528 | 12.468 | 7.73 | 10.285 |
| binarytrees | 28.016 | 24.193 | 27.558 | 1.16 | 3.823 |
| mandelbrot | 9.885 | 8.942 | 9.018 | 1.11 | 0.943 |

## Adopted and rejected experiments

Idiomatic spectral-norm now uses six ordinary row workers at N>=256 and a
serial path for smaller inputs. Its Array representation and each row's
summation order remain unchanged. The previous serial source and full charts
remain in [run 20261031T145604Z](runs/20261031T145604Z/README.md). Tuned spectral-norm stays serial.

The ordinary Counter-object Map implementation did not demonstrate a repeatable
overall gain across the tested k-nucleotide inputs. Keep numeric Map values.
The source, successful correctness checks, active-desktop results, and quiet
paired samples remain preserved in [this run](runs/20261031T161720Z/README.md). This rejects
that implementation rather than all possible Counter or Map improvements.
The earlier `counts[key] += 1` substitution also regressed and remains rejected.

K-nucleotide allocation, short String keys, hashing, and value conversions still
need profiling. N-body and fannkuch retain collection-access and conversion
cost candidates without another demonstrated idiomatic source fix. Parallel
spectral-norm changes elapsed time and CPU consumption; it does not establish a
single-core improvement. No typed containers, SubStrings, raw storage, custom
allocators, or compiler/runtime edits were introduced by this source change.

Earlier Node, reverse-complement Buffer, n-body pair, fannkuch bulk copy, FASTA
Choice records/Buffer, regex JIT, and parallel tree changes remain applied.
All earlier immutable reports and rejected probes remain recoverable. Java
includes startup/JIT. Canonical-size timing remains unrun.
