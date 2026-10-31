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
Summary rows and charts use only the nine problems shared by all eight columns.
No missing value is treated as zero, and no nine-problem summary is compared
with a ten-problem summary.

All displayed runtime data is measured locally with identical configured
inputs. No timings from the Benchmarks Game website are substituted.

## Go contributions

Nine unchanged Go contributions pass the official fixtures and local-profile
checks. They use only the Go standard library. Go k-nucleotide remains N/A:
all five archived variants violate the required ascending lexical order when
frequencies tie. Variants #3/#4/#6 sort keys in descending order; #7/#8 compare
counts only and inherit randomized map iteration. Repeated legal tied-input
checks demonstrate the failures. An independent parent run of #3 prints
T, G, C, A for equal single-letter frequencies. No contribution was patched.

| Problem | Go archive source |
| --- | --- |
| nbody | `nbody/nbody.go-8.go` |
| spectralnorm | `spectralnorm/spectralnorm.go-8.go` |
| fannkuchredux | `fannkuchredux/fannkuchredux.go-8.go` |
| mandelbrot | `mandelbrot/mandelbrot.go-8.go` |
| fasta | `fasta/fasta.go` |
| revcomp | `revcomp/revcomp.go-2.go` |
| binarytrees | `binarytrees/binarytrees.go` |
| regexredux | `regexredux/regexredux.go` |
| pidigits | `pidigits/pidigits.go-7.go` |

Outside configured inputs, the selected Go reverse-complement contribution
wraps output at 60 columns while the selected C contribution preserves short
input wrapping. The selected Go pidigits contribution pads and labels its final
partial group while the selected C contribution omits the final partial-group
count. The configured pidigits inputs are multiples of ten. These are
contribution differences, not source patches or failures on configured inputs.

## Java contributions

Nine unchanged Java contributions pass official fixtures and configured local
workloads on native ARM OpenJDK 27. They use only Java standard libraries.

| Problem | Java archive source |
| --- | --- |
| nbody | `nbody/nbody.java-2.java` |
| spectralnorm | `spectralnorm/spectralnorm.java-8.java` |
| fannkuchredux | `fannkuchredux/fannkuchredux.java-2.java` |
| mandelbrot | `mandelbrot/mandelbrot.java-8.java` |
| fasta | `fasta/fasta.java-2.java` |
| revcomp | `revcomp/revcomp.java-5.java` |
| binarytrees | `binarytrees/binarytrees.java-2.java` |
| regexredux | `regexredux/regexredux.java` |
| pidigits | `pidigits/pidigits.java` |

All six archived Java k-nucleotide contributions were compiled and checked.
The base and #8 variants misorder ties; #6 drops tied keys; #4/#5 throw
`NullPointerException` when requested fragments are absent. Variant #3
counts uppercase frequencies but returns zero for uppercase present target
fragments. The specification does not restrict FASTA input to lowercase.
Java k-nucleotide therefore remains N/A. No contribution was patched.

The selected Java reverse-complement contribution derives output line width
from the first sequence line. The official fixture and configured inputs
use 60 columns.

Java measurements launch a fresh JVM for every sample. They include JVM
startup and JIT compilation. The separate process warmup cannot warm the
measured JVM; these are whole-program elapsed times, not warmed steady-state
Java throughput.
