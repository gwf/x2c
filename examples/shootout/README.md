# x2c Computer Language Benchmarks Game

This suite adopts the ten standard [Computer Language Benchmarks Game
problems](https://benchmarksgame-team.pages.debian.net/benchmarksgame/description/summary.html).
The official specifications own the required algorithms, inputs, work, and
output. These are local comparisons against contributed programs, not
measurements published or accepted by the Benchmarks Game.

[Current results and charts](results/README.md) are preserved in dev, including
the full table, structured data, figures and plotting provenance.

The comparison has eight columns, with coverage recorded per problem:

| File | Implementation |
| --- | --- |
| `main.x` | Idiomatic x2c, using ordinary collections and APIs |
| `tuned.x` | Tuned x2c, including typed containers and borrowed substrings |
| `main.c` | An unmodified contributed C program |
| `main.py` | An unmodified contributed Python program, where admitted |
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

Binary-trees uses one ordinary `Thread` per depth batch in both x2c columns,
matching the adopted C strategy. Each worker owns its temporary tree scopes;
the main thread reads its scalar batch result after joining. The unchanged
`benchmarks/binarytrees/serial.x` preserves the previous serial implementation.
Historical serial runs and paired source comparisons remain in
[Git history](https://github.com/gwf/x2c/blob/b46aa0e12ab1e4356bd6b4942f1fc30ade5faff6/examples/shootout/results/README.md). Neither threading nor parallel execution requires
typed containers or a custom allocator.

Spectral-norm uses six ordinary `Thread` row batches at N>=256 in the
idiomatic program and N>=500 in the tuned program.
Workers read a fixed input Array and write disjoint existing output slots.
Every matrix product joins its workers before the next product reads results;
each row preserves its original summation order. Smaller inputs run serially.
Tuned spectral-norm retains typed Arrays and its original small-input kernels.
The threshold avoids worker overhead at smaller sizes. K-nucleotide uses
ordinary numeric Map values.

Both fannkuch-redux programs use six ordinary `Thread` permutation ranges at N>=9.
Workers own their Arrays, initialize the prescribed rotation order at each
range's starting rank, and retain global checksum parity. Smaller inputs run
serially. Tuned fannkuch retains native integer Arrays and their inexpensive
element-copy loop. K-nucleotide caches
its immutable sequence-length loop bound and retains ordinary numeric Map values.
Seven ordinary Threads count the seven required widths independently. Each
worker builds a full Map (MapSubInt in tuned) and formats its result;
the caller joins and prints
results in specification order. Shared canonical Strings retain output values.

Regex-redux uses nine ordinary Threads for independent counts at cleaned
sequence lengths of at least 65,536 bytes. Each worker owns its Regexp and
retains only a scalar count. The main thread runs the ordered substitution
chain concurrently, joins workers, and prints counts in specification order.
Smaller inputs use the serial path. No Regexp or match-data block is shared.
The tuned workers count directly through their private native PCRE2 match data.
Tuned stripping and replacements use the same native JIT matching with literal
text. Two typed scratch buffers alternate through ordered replacements,
avoiding preliminary sizing scans and canonical intermediate Strings.
Pidigits keeps its existing Spigot owner and GMP lifecycle while calling GMP
directly, without a private Integer forwarding layer.

Reverse-complement keeps the existing input Buffer through `_write`, instead
of converting each complete record into a canonical String. A native
`ptrdiff_t` cursor and the ordinary Buffer.get API avoid narrowing the Buffer
length to int. Complement rules, output lines and record order are unchanged.
The output-line Buffer still uses the existing ordinary String conversion.
The tuned program reads 16 KB chunks, appends sequence spans to ArrayChar,
and retains its in-place complement table. It batches 256 output lines per
write and preserves headers, CRLF handling and final unterminated lines.

Tuned FASTA copies repeated sequence spans and fills reusable native buffers,
writing up to 256 lines together. Random symbols use a full scan of cumulative
probability thresholds with the original boundary rule and random sequence.
Tuned N-body stores five native value records contiguously and updates them
through reference methods. Its interaction order and arithmetic grouping are
unchanged; generic Array iteration and allocated Pair records are removed.

Mandelbrot uses at most six ordinary Threads on 16-row chunks per wave at
N>=256. Caller-owned Arrays are filled before startup; each worker replaces
only existing byte-valued slots in its own Array. Joins precede ordered output.
The next wave releases the previous wave's storage, bounding retained output
to 96 rows. Pixel arithmetic and PBM padding are unchanged. Smaller inputs run
serially. A same-batching serial control separates threading from buffering.
The tuned program uses caller-owned ArrayChar storage and bulk ordered output.

Parallelism follows published Benchmarks Game precedent for each problem. If
other official submissions use it, x2c may use it too; if none do, x2c stays
serial. Algorithm and workload requirements still apply. This policy operates
within the existing idiomatic/tuned definitions and adds no comparison columns
or separate serial/parallel chart regimes.

The adopted C binary-trees program uses pthread workers, Rust spectral-norm
and fannkuch-redux use Rayon, and C k-nucleotide uses OpenMP sections.
The [fannkuch specification](specs/fannkuchredux.html) permits parallel chunks;
[pidigits](specs/pidigits.html) requires its step-by-step serial algorithm.

Rust, C++, Go, and Java each have nine admitted contributions. Their
k-nucleotide cells are `N/A`: Rust and Go candidates fail required tie
ordering; Java candidates fail ordering, absent-fragment, or uppercase-target
checks; C++ candidates need GNU-only headers absent from this toolchain.
[Reference coverage](https://github.com/gwf/x2c/blob/b46aa0e12ab1e4356bd6b4942f1fc30ade5faff6/examples/shootout/results/reference-coverage.md) records the evidence and
the selected contributions' input constraints. Contributions are not patched
to conceal these differences.

Python binary-trees is also N/A. Its previous constant leaves miss required
allocations; the fresh-leaf archived alternative disables GC and is excluded
under the pinned default-GC guidance. The allocation finding is reproduced;
the GC exclusion is an interpretation recorded in the coverage report.

Summary rows and comparison charts use the eight problems shared by all eight
columns. Individual rows retain all admitted cells for the other two problems.
Earlier nine-problem summaries have a different cohort. Reports record their
actual sample counts and admitted programs.

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
The [former custom suite](https://github.com/gwf/x2c/tree/9d196566fe704b9fbcc99c5d16db9d8cac2681cb/examples/shootout-unofficial),
with its previous workloads and C-port variants, remains in Git history.

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

The [historical result](https://github.com/gwf/x2c/blob/b46aa0e12ab1e4356bd6b4942f1fc30ade5faff6/examples/shootout/results/c-through-x2c.md) records all ten native-driver
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
It replaces `baseline.json` and ignored
`examples/build/shootout/results/current.*` only when every
build, check, and measurement succeeds. Run calibration in a quiet window.

An ordinary run rebuilds and measures the two x2c programs against the
pinned C, Python, Rust, C++, Go, and Java statistics. Update explicitly promotes its report.
Raw samples and receipts stay under ignored `examples/build/shootout/`.
The tracked calibration keeps reference statistics, identities, provenance,
and correctness hashes. It omits raw sample arrays and exact-output copies;
numeric tolerance checks retain their small expected values.

The stdin-driven problems receive identical files generated by the adopted
official FASTA C program before timing begins. Their input hashes are pinned
in the baseline. Input generation is excluded from every program's time;
reading stdin and writing the required stdout remain measured. Stdout goes
to `/dev/null` during timing, after output correctness has been checked.

`quick` and `local` use smaller inputs for development and local measurement.
`canonical` records the larger inputs specified upstream. Smaller profiles
do not replace the official output checks and are not official-site scores.
Mandelbrot profile dimensions must be multiples of eight for the unchanged
Rust contribution; spectral-norm dimensions must be even. The local
Mandelbrot size is 512, so every admitted contribution receives
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

Promoted reports at `examples/shootout/results/current.md` and
`current.json` identify the calibration and measured profile.

The old suite's timings are not comparable with these results. Changes to
specifications, references, profile inputs, or dependency flags require a
fresh calibration. Machine checks and environment receipts retain the
existing restrictions on comparisons between hosts.

## Saved reports and charts

The [current snapshot](results/README.md) is tracked in dev. It includes the
latest promoted report and all three chart forms in PNG/SVG/PDF, with CSV
and provenance. A pull brings these files into the checkout.

`make shoot-run` keeps scratch output under ignored `examples/build/shootout/`.
`make shoot-update` promotes its report to tracked `results/current.json` and
`results/current.md`, outside scratch cleanup. Each update also retains a
compact row in [score history](results/history.md); the history records
cohorts and calibration identities so changed comparisons are visible.
Regenerate charts from that
report before committing the snapshot:

```sh
python3 examples/shootout/tools/render-charts.py \
  examples/shootout/results/current.json \
  examples/shootout/results/charts
```

One reusable renderer lives in `tools/render-charts.py`; optional dependencies
are pinned in `tools/requirements-charts.txt`. Rendering uses saved data and
does not rerun benchmarks. Commit report and chart changes together so the
provenance hash and run ID describe one measurement.

Historical reports and experiments remain in
[Git history](https://github.com/gwf/x2c/blob/a9aeff5b843878fd102b31402a522d2f0a1d2d6c/examples/shootout/results/README.md).
Only the current snapshot is retained in the live tree. The
[website integration guide](../../site/BENCHMARKS.md) describes using the
snapshot in a future page.
