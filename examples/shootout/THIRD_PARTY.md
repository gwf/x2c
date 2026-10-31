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

| Problem | Contributed C source in archive | Contributed Python source in archive |
| --- | --- | --- |
| n-body | `nbody/nbody.gcc` | `nbody/nbody.python3` |
| spectral norm | `spectralnorm/spectralnorm.gcc-8.gcc` | `spectralnorm/spectralnorm.python3-6.python3` |
| fannkuch-redux | `fannkuchredux/fannkuchredux.gcc` | `fannkuchredux/fannkuchredux.python3-8.python3` |
| Mandelbrot bitmap | `mandelbrot/mandelbrot.gcc-8.gcc` | `mandelbrot/mandelbrot.python3-8.python3` |
| fasta | `fasta/fasta.gcc` | `fasta/fasta.python3` |
| k-nucleotide | `knucleotide/knucleotide.gcc` | `knucleotide/knucleotide.python3-3.python3` |
| reverse-complement | `revcomp/revcomp.gcc-6.gcc` | `revcomp/revcomp.python3` |
| binary-trees | `binarytrees/binarytrees.gcc-5.gcc` | `binarytrees/binarytrees.python3-2.python3` |
| regex-redux | `regexredux/regexredux.gcc-5.gcc` | `regexredux/regexredux.python3` |
| pidigits | `pidigits/pidigits.gcc` | `pidigits/pidigits.python3-4.python3` |

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
  contribution uses its standard `re` engine.
- Pidigits uses installed GMP for C and both x2c versions. GMP is separately
  distributed under its upstream LGPLv3+/GPLv2+ terms; it is not vendored here.
  The adopted Python contribution uses Python integers.
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
[reference-coverage.md](results/reference-coverage.md). Every admitted source
path and hash is also recorded in `benchmarks.json`.

These implementations and local measurements do not imply upstream
acceptance or endorsement. The suite does not reuse timings from the
Benchmarks Game website.
