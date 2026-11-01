# Tuned sequence and N-body improvements: 20261101T161913Z

Measured clean source: `b81b82c3065ffcfaf900d6febdd9d874ec179b5a`. Before source: `f12c7619a678fd06672e883597de6ca3419fbdea`. Local M4 Max profile, twelve fresh x2c samples after one warmup. All twenty x2c programs were rebuilt, checked and measured. Foreign program sources and calibration `53fdc5b1230c52ce` remain unchanged; foreign timings were not repeated.

## Accepted changes

Reverse-complement reads 16 KB chunks, retains its typed in-place complement kernel and writes up to 256 formatted lines together. Headers, CRLF and missing final newlines are preserved. FASTA copies repeated spans, fills reusable native output buffers and counts cumulative thresholds with its original >= boundary rule. N-body stores five contiguous native records, uses reference methods and removes generic Array iteration and allocated Pair records. Arithmetic grouping and pair order are preserved. No compiler, runtime, package, allocator, idiomatic program or foreign contribution changed.

| Tuned workload / input | Before ms | After ms | After / before | Paired wins |
|---|---:|---:|---:|---:|
| revcomp / 100000 | 5.245 | 1.925 | 0.367x | 12/12 |
| fasta / 100000 | 13.896 | 3.679 | 0.265x | 12/12 |
| nbody / 1000000 | 65.937 | 30.027 | 0.455x | 12/12 |

The accepted comparison uses twelve alternating old/new fresh-process pairs per timed input, with one warmup. Final sweeps check 33 cases and record 216 timings. Fifty-eight additional reverse-complement checks put read boundaries, CRLF, headers and partial output lines around the 16 KB boundary. FASTA checks include zero, tiny, wraparound and output-line sizes; the large random stream spans the generator period. N-body checks compare printed energies at zero through one million steps. All compared stdout bytes match.

Initial isolated probes also pass: reverse input buffering improves 5.294 -> 2.638 ms locally; adding output batching improves 2.661 -> 1.867 ms. FASTA buffering improves 14.015 -> 10.785 ms; full threshold scanning then improves 10.734 -> 3.672 ms. Initial probe logs retain these medians; complete raw samples are archived for the final comparisons and the independent input/buffering/selection probes that were not overwritten by the repeat. No losing candidate was adopted.

At one-million-unit FASTA input, reverse-complement improves 39.351 -> 8.275 ms and FASTA improves 129.970 -> 26.642 ms. Small-input timings remain near process startup and show no observed regression. Raw records retain elapsed/user/system time and peak RSS.

## Updated comparison

Across the eight shared problems, tuned elapsed-time geometric means are 1.242x C, 1.059x Rust, 0.804x C++, 0.605x Go and 0.081x Python. Tuned/idiomatic is 0.461x. These are matched problem ratios of selected programs, not general language rankings. Fresh-process Java includes JVM startup and JIT compilation.

Only the three tuned sources changed. Other measured entries can move between full reruns because of noise; their movements are not claimed as source improvements. Canonical-size timing and foreign recalibration remain unrun.

## Saved evidence and limits

- [Full table](current.md), [structured report](current.json), [paired summary](comparison/summary.json), and [updated chart](charts/runtime-source-size.png).
- `raw/` retains original build/check/run receipts and fresh x2c measurements. The compressed baseline retains the unchanged foreign calibration.
- `comparison/` retains checks, raw final comparisons, initial probe logs, fixed-seed boundary probes and monitoring records. Frozen native binaries remain in ignored local debug storage, not Git. The build/check scripts retain historical absolute paths; use their recorded commands with an equivalent checkout.
- `sources/` preserves before, intermediate and accepted sources and available build receipts. All compared binaries used one compiler/runtime and the same -O2/-DNDEBUG flags.
- `charts/` retains SVG/PNG/PDF, CSV data, rendering source and actual rendering environment. No new recurring gate was introduced.

One-second process snapshots during the full run detect no active outside native compiler. A 26-day-old `make site` process and its development-server descendants were idle at 0% CPU. Ordinary desktop background activity remained; monitoring does not prove zero interference between snapshots. Other agents did not build or time during the campaign. Publication validation is recorded in the completed plan.
