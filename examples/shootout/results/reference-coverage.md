# Reference coverage

The current comparison adopts exact contributions from the pinned archive.
The reference audit screened 70 candidates across all ten problems and six
reference languages. Selection requires specification compatibility, official
fixture and local-output checks, and repeatable local quiet-window gains.

| Problem | C | Python | Rust | C++ | Go | Java |
| --- | --- | --- | --- | --- | --- | --- |
| n-body | `nbody/nbody.gcc` | `nbody/nbody.python3` | `nbody/nbody.rust-6.rust` | `nbody/nbody.gpp-9.gpp` | `nbody/nbody.go-8.go` | `nbody/nbody.java-2.java` |
| spectral norm | `spectralnorm/spectralnorm.gcc-3.gcc` | `spectralnorm/spectralnorm.python3-4.python3` | `spectralnorm/spectralnorm.rust-5.rust` | `spectralnorm/spectralnorm.gpp` | `spectralnorm/spectralnorm.go-4.go` | `spectralnorm/spectralnorm.java-8.java` |
| fannkuch-redux | `fannkuchredux/fannkuchredux.gcc-5.gcc` | `fannkuchredux/fannkuchredux.python3-4.python3` | `fannkuchredux/fannkuchredux.rust-4.rust` | `fannkuchredux/fannkuchredux.gpp` | `fannkuchredux/fannkuchredux.go` | `fannkuchredux/fannkuchredux.java-2.java` |
| Mandelbrot bitmap | `mandelbrot/mandelbrot.gcc-5.gcc` | `mandelbrot/mandelbrot.python3-5.python3` | `mandelbrot/mandelbrot.rust-4.rust` | `mandelbrot/mandelbrot.gpp-9.gpp` | `mandelbrot/mandelbrot.go-6.go` | `mandelbrot/mandelbrot.java-4.java` |
| fasta | `fasta/fasta.gcc-2.gcc` | `fasta/fasta.python3` | `fasta/fasta.rust-4.rust` | `fasta/fasta.gpp` | `fasta/fasta.go-2.go` | `fasta/fasta.java-2.java` |
| k-nucleotide | `knucleotide/knucleotide.gcc` | `knucleotide/knucleotide.python3-3.python3` | N/A | N/A | N/A | N/A |
| reverse-complement | `revcomp/revcomp.gcc-6.gcc` | `revcomp/revcomp.python3` | `revcomp/revcomp.rust-2.rust` | `revcomp/revcomp.gpp` | `revcomp/revcomp.go-2.go` | `revcomp/revcomp.java-5.java` |
| binary-trees | `binarytrees/binarytrees.gcc-5.gcc` | N/A | `binarytrees/binarytrees.rust-2.rust` | `binarytrees/binarytrees.gpp-5.gpp` | `binarytrees/binarytrees.go-5.go` | `binarytrees/binarytrees.java-7.java` |
| regex-redux | `regexredux/regexredux.gcc-5.gcc` | `regexredux/regexredux.python3-2.python3` | `regexredux/regexredux.rust` | `regexredux/regexredux.gpp-6.gpp` | `regexredux/regexredux.go` | `regexredux/regexredux.java-6.java` |
| pidigits | `pidigits/pidigits.gcc` | `pidigits/pidigits.python3-3.python3` | `pidigits/pidigits.rust-2.rust` | `pidigits/pidigits.gpp-4.gpp` | `pidigits/pidigits.go-7.go` | `pidigits/pidigits.java` |

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
Summary rows and charts use only the eight problems shared by all eight columns.
No missing value is treated as zero. Earlier nine-problem summaries use a
different cohort and must not be compared as if their membership were unchanged.

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

## Python binary-trees

The previously adopted #2 returns a constant `(None, None)` tuple at each leaf.
Compiling its unchanged function and checking object identity confirms shared
leaves. Base/#4/#5 have the same source pattern. This fails the pinned work
requirement that leaves receive the same allocation as interior nodes.

The remaining #3 creates fresh list leaves but explicitly calls `gc.disable()`.
It is excluded under the pinned request to use default GC when possible.
This is an interpretation of the GC guidance, distinct from the reproduced
allocation violation. The original source, disassembly, identity evidence,
and rejected-source discussion are preserved with the reference audit.
No patched reference replaces either entry.

There are 75 admitted programs. The eight-column common cohort excludes both
k-nucleotide and binary-trees. Complete Latin rotations for coverage groups of
8, 7 and 4 programs require 56 samples per program, or 4,200 observations.
The harness derives the rotation multiple from manifest availability.
