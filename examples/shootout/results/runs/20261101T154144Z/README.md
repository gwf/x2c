# Tuned source parity: 20261101T154144Z

Measured source revision: `19e79b5026679638e63297fc7f839a97b5aac32c`. Local profile, twelve fresh x2c samples per program after one warmup. Both x2c columns were rebuilt and remeasured across all ten problems. The 55 foreign programs were not rerun; their measurements and source bytes remain pinned to calibration `53fdc5b1230c52ce`.

## Result

The tuned programs now receive the ordinary threading and buffering opportunities already used by their idiomatic siblings, while keeping typed Arrays, borrowed MapSubInt keys and direct PCRE2 counting. No compiler/runtime, package, custom allocator or foreign contribution changed.

| Tuned workload / local input | Before ms | After ms | After / before | Paired wins |
|---|---:|---:|---:|---:|
| fannkuchredux / 9 | 11.916 | 3.609 | 0.303x | 12/12 |
| mandelbrot / 512 | 9.299 | 3.790 | 0.408x | 12/12 |
| spectralnorm / 500 | 7.231 | 6.248 | 0.864x | 12/12 |
| regexredux / 100000 | 54.156 | 26.067 | 0.481x | 12/12 |
| knucleotide / 100000 | 49.049 | 16.363 | 0.334x | 12/12 |
| revcomp / 100000 | 12.206 | 5.704 | 0.467x | 12/12 |

The complete fresh comparison gives a workload-matched tuned/idiomatic geometric mean of **0.665x elapsed time** across the eight shared problems. Its matched-ratio median is 0.793x. These compare the same workload in both columns; they are not quotients of independently sorted summary medians.

## Program changes

- Fannkuch: six global-rank chunks at N>=9; native ArrayInt copying, global checksum parity and joined maximum/checksum reduction.
- Mandelbrot: six 16-row bands per bounded 96-row wave at N>=256; caller-owned ArrayChar outputs and ordered bulk writes, preserving PBM padding.
- Spectral-norm: six row batches at N>=500; typed Arrays and original full-range serial kernels below that threshold. Every matrix product joins before the next reads its outputs; each row retains j-order.
- Regex-redux: nine independent JIT count workers at cleaned input >=65536 bytes; each owns its native match data/context. Ordered substitutions run independently on the caller.
- K-nucleotide: seven width workers, each with its own borrowed MapSubInt and formatted canonical String output. The fixed sequence outlives all workers; output and tie order are unchanged.
- Reverse-complement: bulk ArrayChar input-span appending removes per-character pushes while retaining its complement table, in-place processing and output format.

## Checks and rejected refinements

The standard harness passes official fixtures and local outputs for all twenty x2c programs. The initial matched sweep checks 54 old/new cases and records 672 fresh timings. Numeric refinements check seventeen cases with 336 timings. Final spectral verification checks eleven cases with 240 timings. Checks cover tiny inputs, thresholds, factorial chunks, non-byte-aligned PBM output, partial row waves, empty/short/tied nucleotide input, CRLF and a missing final newline. All compared stdout bytes match the retained original tuned programs.

Typed ArrayInt.setslice copying initially lost about 13-14% at fannkuch N=7/8. The accepted source retains a native copy loop. Spectral threading at N=256/257 lost about 66-81%, and at384 lost about12%; it is enabled only from500, the smallest measured winning size. Direct parameterized serial bands still cost about9-11% at intermediate sizes, so the accepted source retains the original full-range serial kernels. Final checks at255/256/257/384/499 are effectively flat versus the original serial implementation.

Larger inputs also improve: fannkuch N=10, Mandelbrot N=1024, spectral N=1000/2000, and one-million-unit FASTA inputs for the three text workloads were checked and measured. Threading can spend more total CPU and retain more memory to lower elapsed time; raw records include user/system CPU and RSS. This is a local M4 Max result, not a universal threshold or a controlled single-core comparison.

The coordinator accepted all reported timing windows with no detected outside compiler overlap. One early probe setup failed after the harness cleared mutable build output; it produced no comparison and was rerun using frozen binaries. Its failed receipt remains in the archive. Workers only edited source in isolated worktrees and did not build or time concurrently. Quiet-window receipts do not establish zero desktop background activity throughout each sample.

## Saved evidence

- [Full table](current.md), [structured table](current.json), and [matched comparison](comparison/summary.json).
- `raw/` retains original x2c build/check/run receipts and raw measurements, compressed without changing their bytes. Foreign measurements remain in the compressed pinned baseline.
- `comparison/` retains the complete matched sweeps and rejected-candidate evidence. Use the accepted result mapping in summary.json; early sweeps include superseded candidates.
- `sources/` retains before/after tuned sources. Native binaries are in the ignored local debug archive, not Git. The initial rejected fannkuch binary was superseded locally; its source commit, generated/binary hashes and raw records remain recoverable.
- `charts/` contains updated figures, CSV and rendering provenance. Its per-run requirements record the actual plotting versions used. Figures reuse the existing rendering design and state the pinned foreign baseline.

Older immutable runs remain unchanged. The current compiler/runtime is the adopted Map-split baseline; this campaign changes only benchmark programs, their documentation and results. Publication validation is recorded in the completed plan.
