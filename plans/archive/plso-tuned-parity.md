# Bring tuned PLSO programs to source parity

> Status: done - 2026-11-01.
> Tuned source parity and the complete refreshed PLSO comparison are validated
> at `f3a8bc651`; the publication gate passes.

## Result

Retain the idiomatic/tuned definitions, official workloads, pinned foreign
programs and C calibration. Give tuned fannkuch, Mandelbrot, regex-redux,
spectral-norm and k-nucleotide the existing ordinary parallel decomposition.
Keep typed Arrays, borrowed MapSubInt keys and direct PCRE2 counting. Improve
reverse-complement input buffering without changing its typed representation.
Preserve output ordering, checksum parity, row summation order, PBM padding,
worker ownership and per-worker match data. No runtime or allocator changes.

## Implementation and validation

1. Numeric and text workers make disjoint source-only changes in isolated
   worktrees. The orchestrator compiles and checks the combined result once.
2. Retain baseline sources, binaries and local measurements. Check official,
   quick and local outputs plus threshold, padding and borrowed-lifetime cases.
   Compare old/new tuned binaries in alternating fresh processes on the same
   inputs, including larger inputs where startup costs can change the result.
   Adopt useful thresholds from evidence; do not assume threading always wins.
3. Update execution metadata and documentation. Review the authored diff and
   freeze the candidate. Rerun the standard complete x2c PLSO comparison against
   pinned references, retaining raw records and workload-matched summaries.
4. Integrate current dev, run the existing publication gate once for the
   combined authored tree, review generated changes, publish and archive.

## Design review

Reuse the idiomatic programs' ordinary Thread, join and output ownership
patterns. Worker-local mutable state stays local; shared inputs stay fixed.
Specialized data access remains in the tuned kernels. Source-only workers
avoid redundant bootstrap builds and leave timings to one quiet coordinator.

## Delivered evidence

- Six tuned programs retain specialized storage and now use the applicable
  ordinary scheduling/buffering improvements. Source-only workers supplied
  disjoint private commits; the orchestrator compiled and measured the batch.
  No compiler, runtime, package, allocator or foreign program changed.
- Full PLSO update `20261101T154144Z` rebuilds/checks all twenty x2c programs
  and records twelve fresh processes each against the pinned foreign baseline.
  The workload-matched tuned/idiomatic geometric mean is 0.665x elapsed time
  across eight shared problems. It is not a ratio of column medians.
- Twelve-pair source comparisons show local tuned speedups of about 3.3x
  fannkuch, 2.5x Mandelbrot, 1.16x spectral, 2.1x regex, 3.0x k-nucleotide and
  2.1x reverse-complement. Larger inputs also pass and improve.
- Fifty-four initial output comparisons and numeric refinements cover tiny
  inputs, threshold boundaries, non-byte-aligned PBM, partial row waves,
  checksum order, tied/absent nucleotide counts, CRLF and missing final newline.
  Native element copying replaced a slower bulk-copy candidate. Spectral
  retains original serial kernels below the measured 500-row threshold.
- The existing publication gate passes on `f3a8bc651`: 1,164 tests, 103,725
  assertions, 1,380 fixtures, 138 matching book outputs, command checks and
  bootstrap/stage comparisons. No generated compiler/runtime delta remains.
  Five shootout harness tests and the complete archive checksum check pass.
- The immutable [run archive](https://github.com/gwf/x2c/blob/b46aa0e12ab1e4356bd6b4942f1fc30ade5faff6/examples/shootout/results/runs/20261101T154144Z/README.md)
  contains raw records, before/after source snapshots, rejected probes,
  CSV, updated figures in all three formats and rendering provenance.
  Original compiler/native binaries remain local under ignored debug storage.
- Foreign reference timing was not repeated; all 55 contributed sources and
  their calibration remain unchanged. Canonical-size timing and Linux timing
  were not run. Parallelism trades total CPU and peak memory for elapsed time;
  raw receipts preserve both. No new recurring check was introduced.
