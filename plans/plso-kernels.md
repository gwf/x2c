# Close tuned PLSO kernel gaps

> Status: active - 2026-11-01.
> Freeze `f12c7619a`, then measure reverse-complement, FASTA and N-body in order.

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
