# Reference audit and ordinary parallel k-nucleotide

Run `20261031T181939Z`, observed 2026-10-31 11:19 PDT / 2026-10-31 18:19 UTC, measures clean source
`381673a8d6d51098a44f62a635db98c0c9ca927e`. The report checkpoint is `246938ba64124426a4e9dee6aa09e632582994f3`. Subsequent
archive/documentation commits preserve these bytes without changing measured code.

This is the configured **local** profile on Apple M4 Max, not canonical-size
timing or published Benchmarks Game results. All 75 admitted programs pass
both official fixtures and local output checks. Fifty-six fresh-process samples
per program give 4,200 observations. Complete rotating Latin orders balance
all coverage groups (8,7,4 programs). Eight columns share eight problems;
k-nucleotide and binary-trees remain in complete per-problem tables.

The Python binary-trees entry was removed because its constant leaf tuple
misses required allocations. The fresh-leaf archived alternative disables GC
and is excluded under the pinned default-GC-when-possible guidance. The former
is reproduced; the latter is a documented interpretation, not an allocation
finding. All earlier nine-problem reports and figures remain unchanged.

## Quiet evidence and process model

Timing follows six consecutive ten-second observations with at least 90 percent
aggregate CPU idle, after builds and fixtures. The exact observations are in
`current.json` and `raw/reference-profile-quiet-window.jsonl.gz`. This establishes
the pre-run window; it does not establish zero background activity throughout.
Two earlier attempts are retained under `../../evidence/reference-profile/interfered-
attempts/`: one partial run overlapped other tests, and a completed run captured
substantial Contacts/Mail background work. Neither supplies the final figures. The
final process observations have a median external CPU estimate of 22.55 percent of
one core and a maximum of 138.3 percent, across a sixteen-core host. These ps
estimates are distinct from the aggregate idle criterion.

Every timed sample starts a fresh process. Java includes fresh-JVM startup
and JIT compilation. A separate warmup process does not warm measured JVMs.

## Source findings and selected changes

The source audit considered all ten problems across six reference languages
and centrally built 70 candidate configurations. Sources were never patched.
28 stronger compatible reference choices or source-specific build settings
were adopted after correctness checks and quiet confirmation. Existing C
k-nucleotide and regex-redux OpenMP pragmas are now enabled. Other wins include
parallel C/C++ fannkuch, standard-library pooled/threaded C++ binary-trees,
Go parallel entries, Rust scalar/Rayon/direct-GMP entries, and official Python
multiprocessing/GMP/PCRE2 entries. Exact paths and hashes are in `benchmarks.json`.

The focused experiment rotates before programs and candidates for eight local
rounds after a separate quiet window. Adoption requires a median at least 5 percent
lower and at least 6/8 paired wins; the fastest eligible variant per cell wins.
Small or inconsistent differences retain the previous source. These focused
samples are separate from this full calibration.

For idiomatic k-nucleotide, sampled stacks identify String slice/intern-pool
lookup and Map operations as the main hot paths. Seven ordinary Threads now
build the seven required full growing Maps. Worker-local collections do not
escape; canonical String outputs survive callback exit and print after ordered
joins. The quiet probe measured 163.604 ms serial versus 83.901 ms parallel,
with 8/8 paired wins. Sixteen DNA oracle/edge inputs and the larger N=1,000,000
profiling input match the retained oracle. No compiler/runtime source changed.
No typed container, Substr, private pool, raw storage or custom allocator was added.

## Recovery and website integration

- `current.json`, `current.md`, `baseline.json.gz`, `benchmarks.json`: exact run.
- `raw/`: original 4,200 observations, build/check/machine/summary receipts,
  calibration log, quiet observations and orchestration script.
- `charts/`: three standard forms plus focused `reference-audit-probes`, each
  PNG/SVG/PDF; CSVs, renderers and provenance; `website.json` is the curated export.
- `../../evidence/reference-profile/`: all candidate source bytes, failed builds,
  fixture/local outputs, initial and quiet samples, decisions, sample stacks,
  profiling input and receipt, serial/threaded sources, sanity reports and scripts.
- `../../SHA256SUMS`: archive verification. Earlier immutable runs stay unchanged.

Recover each `.gz` with `gzip -dc`. Evidence paths mirror the scratch directory.
To rerender focused probes from a clone, decompress `screen.json.gz`,
`confirm-selected.json.gz`, `confirm-raw.jsonl.gz`, and `decisions.json.gz` into one temporary directory,
then pass that directory to `charts/render-probes.py --output OUT`.
The renderer reads these saved files; it never executes candidate paths.
See [recovery](../../README.md) and [website notes](../../../../../site/BENCHMARKS.md).
Native binaries are reproducible from pinned source and recorded commands;
recorded hashes identify the measured executables, which are not stored in Git.

The optional unchanged-C sanity check passes all 10 native-driver programs.
The parser accepts 7; GNU vector indexing (Mandelbrot), a khash declaration
(k-nucleotide), and an empty parameter list (reverse-complement) remain
unsupported in those unchanged sources. Logs are retained; no C-through-x2c
column is added. The sanity tool now passes compiler-only flags with `-Xcc`.

Canonical-size timing remains unrun.
