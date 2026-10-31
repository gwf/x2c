# x2c Computer Language Benchmarks Game

This suite adopts the ten standard [Computer Language Benchmarks Game
problems](https://benchmarksgame-team.pages.debian.net/benchmarksgame/description/summary.html).
The official specifications own the required algorithms, inputs, work, and
output. These are local comparisons against contributed programs, not
measurements published or accepted by the Benchmarks Game.

The comparison has eight columns, with coverage recorded per problem:

| File | Implementation |
| --- | --- |
| `main.x` | Idiomatic x2c, using ordinary collections and APIs |
| `tuned.x` | Tuned x2c, including typed containers and borrowed substrings |
| `main.c` | An unmodified contributed C program |
| `main.py` | An unmodified contributed Python program |
| `main.rs` | An unmodified contributed Rust program, where admitted |
| `main.cpp` | An unmodified contributed C++ program, where admitted |
| `main.go` | An unmodified contributed Go program |
| `main.java` | An unmodified contributed Java program |

Idiomatic x2c uses ordinary `Array`, `List`, `Map`, `String`, `Buffer`,
classes, and methods where appropriate. It does not use typed containers,
borrowed substrings, raw collection storage, or custom allocation tricks.
Native scalar types and value records remain ordinary x2c. Tuned x2c
uses the language's more specialized operations while meeting the same
specification. A program need not use a feature merely to make the two
versions different. Neither column is a literal C port.

Rust, C++, Go, and Java each have nine admitted contributions. Their
k-nucleotide cells are `N/A`: Rust and Go candidates fail required tie
ordering; Java candidates fail ordering, absent-fragment, or uppercase-target
checks; C++ candidates need GNU-only headers absent from this toolchain.
[Reference coverage](results/reference-coverage.md) records the evidence and
the selected contributions' input constraints. Contributions are not patched
to conceal these differences.

Summary rows and comparison charts use the nine problems shared by all eight
columns. Individual problem rows still include k-nucleotide for C, Python,
and the two x2c implementations. No summary mixes a nine-problem column with a
ten-problem column.

x2c can also express C directly. That capability is understood and has no
separate column. The C column measures an actual contributed C program.

## Adopted problems

| Problem | Required work |
| --- | --- |
| n-body | Advance the prescribed five-body simulation |
| spectral-norm | Estimate the implicit matrix's spectral norm |
| fannkuch-redux | Enumerate permutations, flip prefixes, and report checksum and maximum |
| mandelbrot | Write the actual binary PBM bitmap |
| fasta | Generate the prescribed DNA sequences with the specified random generator |
| k-nucleotide | Count all fragments of each required length in growing hash tables |
| reverse-complement | Read FASTA records and write their reverse complements |
| binary-trees | Allocate every node, including leaves, with stretch and long-lived trees |
| regex-redux | Execute the prescribed regular-expression searches and substitutions |
| pidigits | Generate decimal digits with the prescribed arbitrary-precision spigot |

The separate upstream startup experiment is not one of these ten problems.
The [former custom suite](../shootout-unofficial/README.md) preserves the
previous workloads, C-port variants, and historical results. The active
targets do not run it or mix its measurements with this suite.

## Sources and specifications

`benchmarks.json` records the adopted upstream revision, archive hash,
reference source paths and hashes, official fixture hashes, profile inputs,
and specification links. `specs/` contains unchanged snapshots of those
specifications from the same revision. See [THIRD_PARTY.md](THIRD_PARTY.md)
for attribution and dependencies.

References retain their exact upstream bytes, including original whitespace
and line endings. The narrow whitespace attributes cover only those
third-party files. Change an adopted reference only by selecting another
identified upstream contribution, then recalibrate the suite.

## Build and check

After the normal compiler build:

```sh
make shoot-check
```

This optional command builds every available implementation, checks the official
fixtures, and compares the quick-profile outputs. PBM output is compared as
binary data. N-body uses the official absolute tolerance of `1e-8`.

To check a subset:

```sh
python3 examples/shootout/tools/shootout.py check --profile quick \
  --only mandelbrot --only binarytrees
```

PCRE2 uses the existing pinned `packages/pcre2` build and its native response
file. GMP must be installed for pidigits. C++ uses the configured `CXX`
(default `clang++`). Rust uses `CARGO` (default `cargo`), the checked-in
manifest and lockfile, and the installed stable toolchain. Cargo fetches
the pinned libraries into its ordinary cache and reuses build outputs under
ignored `examples/build/shootout-rust/`. On macOS, dependencies default to
`/opt/homebrew` on arm64 and `/usr/local` on x86_64. Set
`SHOOTOUT_DEPENDENCY_PREFIX` for another prefix. `SHOOTOUT_CPPFLAGS` and
`SHOOTOUT_LDFLAGS` override the corresponding default flags. No packages are
installed into the host by the harness.

Go and a native JDK must be available for reference builds. Set `GO`, `JAVA`,
and `JAVAC` to explicit executables when they are not on `PATH`. Go builds
use `GOENV=off`, `GOTOOLCHAIN=local`, `GO111MODULE=off`, and
`CGO_ENABLED=0`. The harness does not download modules or compilers. Java compiles a byte-identical
copy under the contributed main class name and launches its compiled classes.

Java uses a fresh JVM for each sample, matching the suite's fresh-process
method. Its elapsed time includes JVM startup and JIT compilation. The
separate warmup process does not warm the measured JVM. These results describe
whole-program execution, not Java's warmed steady-state throughput. Compiler
and runtime versions, build commands, class hashes, and Go build settings are
recorded in the receipts.

The adopted k-nucleotide Python program assumes multiprocessing `fork`.
Its launcher selects that start method before executing the unchanged
source. This preserves its Linux process behavior on macOS.

## Check unchanged C through x2c

```sh
python3 examples/shootout/tools/check-c-through-x2c.py
```

This optional check separates `x2c build` of unchanged `.c` inputs from
actual x2c parsing of byte-identical `.x` copies. It records source hashes,
commands, diagnostics, fixture checks, and profile-output comparisons under
ignored `examples/build/shootout-c/`. It continues through every problem and
returns nonzero if any parser or native-driver check fails. It adds no timing
column or recurring publication requirement.

The [recorded result](results/c-through-x2c.md) shows all ten native-driver
checks passing and seven parser checks passing. The three parser rejections
remain visible; the C references are not rewritten to make them pass.

## Measure

```sh
make shoot-calibrate
make shoot-run
make shoot-update
```

Calibration builds, checks, and measures every available implementation together.
It rotates their order across complete Latin cycles after one process
warmup. The default sample count is the smallest balanced count of at least
twelve samples for every coverage group (16 for eight- and four-column rows).
It replaces `baseline.json` and `results/current.*` only when every
build, check, and measurement succeeds. Run calibration in a quiet window.

An ordinary run rebuilds and measures the two x2c programs against the
pinned C, Python, Rust, C++, Go, and Java statistics. Update explicitly promotes its report.
Raw samples and receipts stay under ignored `examples/build/shootout/`.

The stdin-driven problems receive identical files generated by the adopted
official FASTA C program before timing begins. Their input hashes are pinned
in the baseline. Input generation is excluded from every program's time;
reading stdin and writing the required stdout remain measured. Stdout goes
to `/dev/null` during timing, after output correctness has been checked.

`quick` and `local` use smaller inputs for development and local measurement.
`canonical` records the larger inputs specified upstream. Smaller profiles
do not replace the official output checks and are not official-site scores.
The local Mandelbrot size is 512, so every admitted contribution receives
the same dimensions supported by the unchanged Rust program. The official
fixture size (200) and canonical size (16000) are unchanged.
To calibrate and run at those official performance sizes, select the profile
explicitly for both commands:

```sh
python3 examples/shootout/tools/shootout.py calibrate --profile canonical
python3 examples/shootout/tools/shootout.py run --profile canonical
```

Calibration replaces the pinned baseline for the selected profile. The
checked-in baseline uses `local`; the complete canonical run includes the
much longer Python reference executions.

Execution-time ratios use the selected contributed C program as `1.00`.
Source-line ratios use the selected contributed Python program as `1.00`.
Source lines exclude blank and comment-only lines. Python comments are
removed with Python tokenization, preserving floor division and string
contents. C, C++, Rust, and x2c use C-style comment removal; Rust lifetimes
are distinguished from character literals. Go raw strings retain their contents.
Reports identify both x2c variants; the median and arithmetic mean are
orientation aids, not language rankings. Raw data also records process CPU
time, peak RSS, source size, and build information.

The [current report](results/current.md) and [raw data](results/current.json)
identify the calibration and measured profile.

The old suite's timings are not comparable with these results. Changes to
specifications, references, profile inputs, or dependency flags require a
fresh calibration. Machine checks and environment receipts retain the
existing restrictions on comparisons between hosts.

## Recover results and website materials

The [results archive and recovery guide](results/README.md) preserves all four
chart sets, saved reports, raw observations and receipts, paired experiments,
rendering requirements, and checksums on `dev`. The
[website integration guide](../../site/BENCHMARKS.md) identifies the curated
public assets and interpretation requirements.
