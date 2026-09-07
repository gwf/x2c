# x2c Map benchmarks

> Experimental internal benchmarks, separate from the curated x2c examples.

There is no universal hash-table benchmark. These benchmarks use two established,
reproducible suites with different strengths:

- Jackson Allan's
  [C/C++ Hash Tables Benchmark][jackson] measures seven individual operations,
  emits raw CSV plus interactive graphs, and has documented adapter and
  workload definitions.
- Attractive Chaos's [udb3][udb3] measures CPU time and peak memory together
  for counting and mixed insertion/deletion workloads.

The existing `make map-benchmark` remains the quick direct-C regression against
pinned `khashl`. These external suites answer the broader comparison question.

The direct runner writes a fresh timestamped directory containing its frozen
binary, exact `map.x`, raw CSV, metadata, and summary. To compare two retained
production binaries in rotated order, run:

```sh
./unittest/benchmarks/hash-table/direct/compare.py \
  --baseline-binary PATH --baseline-source PATH \
  --candidate-binary PATH --candidate-source PATH \
  --baseline-label before --candidate-label after
```

It compares the production Var Map unless told otherwise. `--implementation`
selects any lane the runner measures, so a candidate for the native maps is
paired and interleaved the same way instead of being read off a single run:

```sh
./unittest/benchmarks/hash-table/direct/compare.py \
  --implementation x2c-typed ...
```

The checksum partner follows from the lane, `khashl` for the Var maps and
`khashl-typed` for the native ones; `--reference` overrides it. A single
unpaired run of the typed lanes moves several percent between invocations, so
a candidate worth two or three percent cannot be judged without this.

The direct operation set includes growing and reserved insertion, replacement,
numeric `Map.updateindex(..., <+>, ...)`, hit and miss lookup, hit and miss
erasure, and iteration. Checksums must match between x2c, khashl, and both
production binaries before timing deltas are emitted. Hit operations use a
key order shuffled independently from insertion, so record allocation order
cannot favor one layout.

## Generated typed Map lane

`lib/typed-map.x` generates `MapIntInt` from the same `$map.core.family` and
`$map.typed.family` expansions that `lib/map.x` uses, with `int` keys and
values stored in the record instead of `Var`. It is shipped runtime code, not
a benchmark specimen, so it isolates the cost of the `Var` value layer from
the cost of the table.

Two lanes measure it:

- The direct runner adds `x2c-typed` and a matched `khashl-typed` reference
  over the same `int` keys and values. `summary.csv` reports both pairs and
  the `x2c_over_x2c_typed` ratio, which is the `Var` layer's share of each
  operation.
- udb3 runs `x2c_typed` beside the labeled production `x2c_map` control in the
  standard profile. Both controls use the same driver shape as `udb3/test.c`,
  so their table sizes and checksums match the cohort.

## Runtime-free U32Map lane

`x2c/u32-map.x` is a benchmark-only extraction of the production Map storage
algorithm for 32-bit keys and values. It keeps eight-byte hash/index slots,
separate eight-byte records, dynamic probe-sequence lengths, Robin Hood
displacement, back-shift deletion, and record-index reuse. It remains the
split-layout specimen even though production Map uses parallel hash and
entry arrays. Its 0.75 load factor matches production Map and khashl.
It replaces `Var`, `Scope`, `Bytes`, and dynamic updates with
`malloc`/`realloc`/`free` and direct typed value pointers. It does not include
or depend on `lib/map.x`.

The x2c source compiles to private static C. A plain-C bridge includes that
generated C and exports the benchmark ABI; the resulting scalar binaries do
not link `libx2c.a`. The runner enforces that with `nm` and `otool`, runs a
million-operation differential test against pinned khashl, and runs ASan and
UBSan before either external suite.

The runner uses Jackson's upstream
`uint32_uint32_murmur` blueprint and passes each suite's exact 64-bit hash to
U32Map, which stores its low 32 bits and maps zero to one. It retains a
labeled production Map udb3 control in the standard profile. Standard `-O3`
and equal `-flto` profiles use the same flags for every timed implementation;
the production control stays standard-only because the existing runtime
archive was not built under the equal-LTO profile.

Run the complete smoke or campaign with:

```sh
make map-u32-benchmark-smoke
make map-u32-benchmark-campaign
```

Or select a suite, profile, or single implementation:

```sh
./unittest/benchmarks/hash-table/run.py smoke --suite jackson \
  --profile standard --implementation x2c_u32
./unittest/benchmarks/hash-table/run.py full --suite udb3 --profile lto \
  --implementation khashl --no-production-control
```

The counter-only profiler runs the same full 80-million-input udb3 workloads
without changing the timed implementation:

```sh
./unittest/benchmarks/hash-table/run.py profile --suite udb3 \
  --profile standard --no-production-control
```

`U32_MAP_PROFILE` enables probe, displacement, expansion, record-reuse, and
back-shift counters in a separate binary. Those counters are preprocessor
no-ops in every timed build. The runner retains raw output and a normalized
`udb3/counters/summary.tsv` in a new timestamped result directory.

Each invocation creates a new timestamped directory under
`unittest/build/benchmarks/hash-table/results/`. It retains raw output,
normalized tables, compiler commands and flags, source and compiler checksums,
suite revisions, sanitizer output, and runtime-symbol audits. A failed or slow
run remains in place with its status; performance thresholds classify results
and never trigger cleanup.

### Optimization research

`research.py` derives named `.x` variants from the retained pre-optimization
commit, translates every variant normally, and runs them in rotated order. It
never edits generated C. Each variant is differential-tested against khashl,
symbol-audited, compiled to assembly with Clang inline diagnostics, and
checksum-matched under both udb3 workloads before its timing is summarized.

For a quick screen or a longer finalist comparison:

```sh
./unittest/benchmarks/hash-table/research.py --repeats 3 \
  -N 20000000 -n 2500000 -k 5
./unittest/benchmarks/hash-table/research.py \
  --variants baseline portable-core all-hinted \
  --repeats 5 -N 80000000 -n 10000000 -k 11
```

Later experiments can instead use the current applied U32Map as their
control. The parallel-key-array experiment is intentionally available only
in this mode:

```sh
./unittest/benchmarks/hash-table/research.py --source current \
  --variants baseline parallel-keys \
  --repeats 3 -N 80000000 -n 10000000 -k 11
```

Every invocation creates a new directory under
`unittest/build/benchmarks/hash-table/research/results/`, including the exact
derived x2c source, generated C, raw output, assembly, inlining reports,
checksums, run order, and normalized table. The baseline source is read from
commit `8c851593`, so later improvements to `x2c/u32-map.x` do not move the
ordinary control. `--source current` is explicit and records the current
source checksum alongside each derived variant. See
[RESEARCH.md](RESEARCH.md) for the retained findings and the
production-portability assessment.

The older Var adapters and shell runners described below remain available and
unchanged for the shipped-Map control campaign.

## Comparing implementations fairly

- The adapters use the checked-in `lib/map.x` and `lib/typed-map.x` without
  benchmark-only changes and call only their production C API.
- `khashl-typed` is given the fmix64 hash `lib/typed-map.x` computes for
  `MapIntInt`, so the native pair differs only in table storage, exactly as the
  `Var` pair does. The copy of that hash is in `direct/map-comparison.c`.
- Map keys and values are pre-boxed as eight-byte `Var` values before Jackson's
  timed regions. A narrow C ABI header lets the C++ suite call the production
  Map symbols directly despite x2c's C-only generated headers; it adds no
  wrapper to timed operations. All Jackson competitors store the same `Var`
  key and value types and call production `Var_hash` and `Var_equal`.
- The `string` profiles use Jackson's established 16-character C-string key
  shape. The C++ tables use its FNV-1a hash and `strcmp`; Map receives the same
  bytes as pre-interned x2c Strings and uses production `Var_hash` and
  `Var_equal`. Key construction stays outside every timed region. Jackson's
  benchmark supplies only default values, so its ordinary 64-bit value is
  retained rather than reporting string values it never reads.
- Every x2c table and Jackson comparison uses a `0.75` maximum load factor,
  matching khashl. The primary `matched` profile applies it to every adapter:
  U32Map, `ankerl::unordered_dense`, `tsl::robin_map`,
  `ska::bytell_hash_map`, and `std::unordered_map`.
- Historical result directories retain the policies recorded in their own
  metadata; changing the current configuration does not relabel them.
- Jackson's stock ankerl and Boost shims declare the supplied hash to be a
  native-width avalanching hash. Production `Var_hash` returns 32 bits, so the
  x2c-specific copies omit that incorrect marker and allow those tables to
  apply their normal defensive mixing. The hash value supplied by the blueprint
  is still exactly `Var_hash`; no benchmark-side replacement hash is
  introduced.
- The Jackson `fixed-policy` profile includes Boost and Abseil because they are
  important reference points, but their flat tables ignore load-factor
  setters. Its output is context, not a matched-load-factor ranking.
- The udb3 adapter calls `Map_updateindex` for the counting workload so Map
  performs a single production lookup/update. The mixed workload calls
  `Map_try_del` and, on a miss, `Map_set`. udb3 intentionally compares each
  table's production load-factor policy and reports the speed/memory tradeoff.
  Upstream adapters use udb3's requested hash; Map keeps its non-injectable
  production `Var_hash`. Consequently this lane measures the shipped Map as a
  whole and does not isolate its storage layout from its hash function.
- No adapter reads Map internals, reserves a benchmark-only layout, substitutes
  a different hash, or adds a fast path that could not be ported unchanged to
  production `map.x`.

Jackson asks iteration adapters to begin at a randomly selected existing key.
Map's public lookup does not expose a cursor, so the first timed iterator
increment derives a cursor from that key's production hash and `Map_len`.
This costs one hash and one length read per 1,000 iterated entries while
avoiding a misleading always-cached start at the beginning of the record array.
The pinned suite labels this operation as 5,000 entries, but its implementation
breaks after 1,000. `summary.tsv` normalizes the actual 1,000 executed
operations and leaves the upstream CSV unchanged.

## Reproduction

The runners pin exact upstream commits and put checkouts, executables, raw
logs, normalized TSV summaries, upstream CSV, and HTML under the ignored
`unittest/build/benchmarks/hash-table/` directory. Results created before the
relocation remain untouched under `examples/build/hash-table-benchmark/`.

An optimized x2c runtime is required:

```sh
make optimize
make clean
make x2c
make map-standard-benchmark-smoke
```

The smoke target compiles every adapter and runs small versions of both
workloads. The complete campaign is intentionally optional and long-running:

```sh
make map-standard-benchmark-campaign
```

Individual lanes can be run directly:

```sh
./unittest/benchmarks/hash-table/run-jackson.sh full matched
./unittest/benchmarks/hash-table/run-jackson.sh full fixed-policy
./unittest/benchmarks/hash-table/run-jackson.sh full pointer
./unittest/benchmarks/hash-table/run-jackson.sh full string
./unittest/benchmarks/hash-table/run-jackson.sh full string-fixed-policy
./unittest/benchmarks/hash-table/run-udb3.sh full
```

Set `UDB3_IMPLEMENTATIONS` to a space-separated subset when isolating a udb3
adapter. The default cohort is x2c, Verstable, khashl, CC, STC,
robin-hood-hashing, ska::bytell_hash_map, and ankerl::unordered_dense.

## Interpreting results

Before treating rankings as broadly representative, run the full campaign on
at least two current CPU families, inspect matching udb3 checksums, and record
compiler and host metadata with the results. The long campaign remains an
optional internal benchmark and must not be added to `make examples`,
`make check`, or `make precommit`.

[jackson]: https://github.com/JacksonAllan/c_cpp_hash_tables_benchmark
[udb3]: https://github.com/attractivechaos/udb3
