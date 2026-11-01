# Close tuned PLSO kernel gaps

> Status: done - 2026-11-01.
> Source candidate `b81b82c30`; archive and publication gate pass at `f1a6244cc`.

## Result and choices

Improve the three tuned programs without changing their official workloads,
output, foreign sources, compiler or runtime. Retain idiomatic programs as
controls. Reverse-complement uses chunk reads and batched formatted output;
FASTA fills reusable buffers and tests probability selection separately;
N-body uses five contiguous native value records and reference methods instead of
boxed Array iteration and allocated Pair records. Preserve arithmetic order.

## Implementation and evidence

1. Freeze before sources, binaries and toolchain hashes. Compare each isolated
   candidate with alternating fresh processes on local and larger inputs.
   Verify output equality, including tiny inputs, buffer boundaries, CRLF and
   missing final newlines. Keep useful gains that repeat; retain rejected data.
2. Review the completed source changes. Commit the candidate before a full
   twelve-sample x2c PLSO update against the unchanged foreign calibration.
3. Archive source comparisons, raw measurements and charts. Integrate current
   dev, run the existing publication gate, review artifacts and publish.

## Design review

Use existing Block storage, typed indexing, value classes and reference
methods. No runtime API, custom allocator, SIMD contract or comparison column
is needed. Before/after binaries share one compiler/runtime and native flags.
Profile only when a candidate's result needs explanation; do not expand the
campaign to regex-redux or unrelated compiler work.

## Accepted source experiments

Twelve alternating pairs per timed input verify output equality. Final local
medians are reverse-complement 5.245 -> 1.925 ms, FASTA 13.896 -> 3.679 ms,
and N-body (one million steps) 65.937 -> 30.027 ms. Larger text inputs also
improve; tiny inputs do not regress. Separate reverse input/output and FASTA
buffering/selection sweeps retain their own frozen source and binary receipts.
Fifty-eight additional reverse-complement cases cover read/output boundaries.
A source-only independent review finds no concrete defect. N-body uses a native
record because nested value classes would require unused equal/hash methods.

## Delivered evidence

The complete run `20261101T161913Z` checks all twenty x2c programs and records
240 fresh observations against the unchanged foreign calibration. Across eight
shared problems, tuned elapsed time is 1.242x C and 1.059x Rust, down from
1.769x and 1.508x. SVG/PNG/PDF figures and their source data are refreshed.
The [immutable archive](https://github.com/gwf/x2c/blob/b46aa0e12ab1e4356bd6b4942f1fc30ade5faff6/examples/shootout/results/runs/20261101T161913Z/README.md)
retains paired measurements, intermediate sources, raw receipts, checks and
rendering provenance. All 1,438 archive checksums pass. The five harness tests
pass. All 55 foreign source files remain byte-identical.

`agent-pr-check` passes: 1,164 tests and 103,725 assertions, compiler fixtures,
138 matching book outputs, command checks and generated-stage comparisons.
No compiler/runtime/bootstrap artifact delta remains. Final closeout only
changes Markdown and reuses the valid compiler proof with doc-check.
Canonical-size timings and foreign recalibration were not run. Process
snapshots detected no active outside native compiler; ordinary desktop
activity remained. No further map or regex change was attempted.
