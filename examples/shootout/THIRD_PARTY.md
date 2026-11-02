# Third-party notices

The reference C, Python, Rust, C++, Go, and Java programs are unmodified contributions from the
Computer Language Benchmarks Game. Their original contributor notices remain
in each source. The x2c versions adapt the algorithms and constants of those
contributions while following the pinned official problem specifications.

Upstream repository: [benchmarksgame-team/benchmarksgame](https://salsa.debian.org/benchmarksgame-team/benchmarksgame).
The adopted revision is `40296663ed350d5fe4a6ab5e367bab61cb77c219`.
All reference programs come from its `public/download/benchmarksgame-sourcecode.zip`.
The archive SHA-256 is:

```text
aabcf6726cdc14f0f45b99e5daba48584f94bbb48883fd3711a1d040474d1cb4
```

`benchmarks.json` records individual source and fixture hashes. Official
specifications and input/output fixtures come from that same revision.

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

The upstream BSD notice is retained in [LICENSE.BENCHMARKSGAME](LICENSE.BENCHMARKSGAME).
The copyright symbol in that license is rendered as ASCII `(c)`. Reference
sources, specification snapshots, and official fixtures retain their bytes.
Original x2c code and harness changes use the [BSD 3-Clause license](LICENSE).

Go and Java contributions use their standard libraries unless a selected
source records another dependency. Their archive paths and hashes are pinned
in `benchmarks.json`; Java filenames may change only for compilation, with
source bytes retained.

## Native dependencies

- The adopted k-nucleotide C program uses klib `khash.h`, distributed under
  the MIT license included in that header. Its pinned revision and hash are
  recorded in `benchmarks.json`. Both x2c variants use existing runtime maps.
- Regex-redux uses the existing pinned [PCRE2 package](../../packages/pcre2/README.md).
  C and both x2c versions link the same package dependency. The Python
  contribution calls the installed PCRE2 through ctypes. Its unchanged source
  uses `find_library("pcre2-8")`; the audit receipt records the resolved library.
- Pidigits uses installed GMP for C and both x2c versions. GMP is separately
  distributed under its upstream LGPLv3+/GPLv2+ terms; it is not vendored here.
  The adopted Python contribution calls the installed GMP through ctypes.
  Rust pidigits now uses its archived direct GMP FFI entry.
- Rust contributions use the libraries pinned in `rust/Cargo.toml` and
  `rust/Cargo.lock`: Rayon, typed-arena, regex, Rug, and gmp-mpfr-sys.
  Cargo retains their upstream licenses with the downloaded packages. Rug
  uses the installed GMP for the admitted pidigits implementation.
- C++ pidigits uses the installed GMP C++ interface. C++ regex-redux uses
  the same pinned PCRE2 dependency and the unmodified Boost 1.46
  `noncopyable.hpp` header. Its source revision and hash are recorded in
  `benchmarks.json`; the Boost license is retained under
  `benchmarks/regexredux/vendor/LICENSE_1_0.txt`.

The added source selections and coverage limits are listed in
[reference-coverage.md](https://github.com/gwf/x2c/blob/b46aa0e12ab1e4356bd6b4942f1fc30ade5faff6/examples/shootout/results/reference-coverage.md). Every admitted source
path and hash is also recorded in `benchmarks.json`.

These implementations and local measurements do not imply upstream
acceptance or endorsement. The suite does not reuse timings from the
Benchmarks Game website.

The current C k-nucleotide, regex-redux, spectral-norm and fannkuch-redux
builds enable their archived OpenMP directives using the installed native
libomp. C Mandelbrot also uses OpenMP and disables floating-point contraction,
matching the source's no-FMA requirement without an x86-only target flag.
The manifest records the exact source-specific compiler and linker settings.
No reference source has been edited.

Python binary-trees is excluded. The previous entry shares a constant tuple
for leaves; its unchanged bytes and allocation evidence are retained with the
reference audit. The fresh-leaf alternative disables GC, which this comparison
excludes under the pinned default-GC-when-possible guidance. This GC decision
is an interpretation of that guidance, separate from the proven leaf reuse.
