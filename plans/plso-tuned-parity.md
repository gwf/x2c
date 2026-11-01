# Bring tuned PLSO programs to source parity

> Status: active - 2026-11-01.
> Gary authorized bringing applicable ordinary threading and buffering
> improvements into tuned programs while retaining specialized storage.

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
