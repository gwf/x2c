# Added reference coverage

Rust and C++ each contribute nine unchanged programs from the same pinned
Benchmarks Game source archive as the existing C and Python references.
All nine selected programs in each language pass the official fixtures and
the configured local workload checks.

| Problem | Rust archive source | C++ archive source |
| --- | --- | --- |
| n-body | `nbody/nbody.rust` | `nbody/nbody.gpp-3.gpp` |
| spectral norm | `spectralnorm/spectralnorm.rust-3.rust` | `spectralnorm/spectralnorm.gpp` |
| fannkuch-redux | `fannkuchredux/fannkuchredux.rust-2.rust` | `fannkuchredux/fannkuchredux.gpp-3.gpp` |
| Mandelbrot bitmap | `mandelbrot/mandelbrot.rust-4.rust` | `mandelbrot/mandelbrot.gpp-3.gpp` |
| fasta | `fasta/fasta.rust-4.rust` | `fasta/fasta.gpp` |
| k-nucleotide | N/A | N/A |
| reverse-complement | `revcomp/revcomp.rust-2.rust` | `revcomp/revcomp.gpp` |
| binary-trees | `binarytrees/binarytrees.rust` | `binarytrees/binarytrees.gpp-2.gpp` |
| regex-redux | `regexredux/regexredux.rust` | `regexredux/regexredux.gpp-6.gpp` |
| pidigits | `pidigits/pidigits.rust-4.rust` | `pidigits/pidigits.gpp-4.gpp` |

## Input constraints

The local Mandelbrot input changes from 500 to 512 for every implementation.
The selected Rust contribution rounds its dimension down to a multiple of
eight. The official fixture (200), quick input (64), new local input (512),
and canonical input (16000) all meet that constraint. The source is unchanged.

The selected Rust spectral-norm contribution requires even dimensions. All
configured profiles and the official fixture use even dimensions. The selected
C++ contribution prints `1` for the extra N=1 check, while the C reference
prints `1.000000000`; those values agree but the text differs. Its official
fixture and configured local input match exactly.

## k-nucleotide exclusions

The pinned specification requires descending frequency and then ascending
lexical keys when counts tie. Rust and C++ k-nucleotide remain unavailable
in this comparison; their programs were not rewritten.

For Rust, all eight source variants in the pinned archive were built unchanged
and tested on a legal FASTA THREE sequence containing `ACGT` repeated 1000
times, wrapped at 60 columns. The first four output lines must be:

```text
A 25.000
C 25.000
G 25.000
T 25.000
```

The base and #2 variants sort by frequency without the required lexical
secondary key, so ties can appear in other orders. Variants #3, #4, #5, #6,
#7, and #9 emit G, T, C, A. Variants #4 and #5 also panic when a requested
fragment is absent. Parent reproduction of the base variant confirms the
wrong tie order. Official-fixture success alone does not establish that
the required ordering is implemented.

For C++, all three source variants require GNU PBDS headers. The configured
Apple clang++ toolchain uses libc++, which does not provide those headers.
A probe supplying the exact public PBDS header then requires GNU-private
`bits/c++config.h`. No compiler or standard library was installed.

Source inspection also finds that the base C++ comparator compares counts
only, while #2 and #3 put results into a `std::map` keyed solely by count,
which cannot retain every key when counts tie. These C++ ordering issues
are source findings, not reproduced runtime findings on this host.

## Comparison cohort

Per-problem tables show all ten problems and mark unavailable cells N/A.
Summary rows and charts use only the nine problems shared by all six columns.
No missing value is treated as zero, and no nine-problem summary is compared
with a ten-problem summary.

All displayed runtime data is measured locally with identical configured
inputs. No timings from the Benchmarks Game website are substituted.
