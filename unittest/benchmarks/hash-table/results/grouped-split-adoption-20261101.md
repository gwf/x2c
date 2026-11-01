# Large grouped Map hash-storage adoption

Measured candidate: `0fce29c16` (`split cached hashes in large grouped maps`), compared with the retained production runtime at `4f6266b7b`. This report concerns adoption of the split policy; earlier full-cohort and Robin Hood retirement results remain historical evidence.

## What changed

The single grouped generator now separates full hashes from controls at 65,536 buckets for Var Map and PoolTable. Smaller tables retain combined storage. Typed families retain their native records and hash policies. The probing algorithm and prefetch policy are unchanged.

Large caches use the existing controls Block lifetime. The aligned trailer holds the cached-hash pointer. Guarded construction frees staged storage on failure. Rebuild transfers the staged cache lifetime to the old controls owner before publishing the replacement. Existing Block cleanup, owner moves and Context export carry that lifetime. Root Pool retains its existing append-only atomic index and version retention.

This introduces an internal storage Scope and a full-hash allocation for a large table. It preserves the public Map/Pool structs, signatures, lazy Map content ownership and root acquire/release publication. There is no new allocator, global lock or runtime backend selector.

## Integer time and memory

Identical 80-million-input udb3 counting and mixed streams, three fresh processes per backend/container/workload in rotated order. Both complete runtimes use O3/DNDEBUG without LTO. The baseline is the retained production archive; the candidate replaces the four generated Map-family objects in it. Every checkpoint length and checksum matches. CPU is ns/input. Memory is upstream adjusted process peak above the pre-test baseline, in decimal MB.

| Container / workload | Baseline ns/input | Adopted ns/input | Adopted / baseline | Baseline MB | Adopted MB |
|---|---:|---:|---:|---:|---:|
| var / count | 94.5 | 91.5 | 0.968x | 1406.6 | 1082.0 |
| var / mixed | 54.2 | 54.8 | 1.011x | 714.5 | 579.6 |
| typed / count | 21.3 | 21.3 | 1.000x | 541.6 | 537.2 |
| typed / mixed | 27.8 | 29.3 | 1.054x | 294.2 | 294.7 |

Var counting adjusted RSS falls about 23%, and mixed RSS about 19%. Headline Var CPU remains close to the existing grouped backend. The native typed mixed row initially looked about 5% slower; five additional alternating pairs give 27.1 ns/input baseline versus 27.8 adopted, about 2.6% slower. That smaller measured cost is retained rather than dismissed.

## Direct operations

Canonical Var and native typed direct-driver functions are copied unchanged, with their named dependency closure. Three rotated fresh processes at each of 8,192, 32,768 and 1,048,576 entries use four probes per key and eight iteration passes. Operation counts and checksums match between backends. Selected medians in elapsed ns/operation:

| Container / entries / operation | Baseline | Adopted |
|---|---:|---:|
| x2c / 8,192 / update-add-hit | 23.804 | 24.048 |
| x2c / 32,768 / lookup-hit | 8.545 | 8.492 |
| x2c / 1,048,576 / grow-insert | 25.631 | 24.291 |
| x2c / 1,048,576 / lookup-hit | 15.435 | 17.531 |
| x2c-typed / 8,192 / update-add-hit | 4.028 | 3.723 |
| x2c-typed / 32,768 / lookup-hit | 3.647 | 3.555 |
| x2c-typed / 1,048,576 / grow-insert | 16.624 | 16.269 |

These short direct observations carry more timing noise than the longer targeted confirmations in the preceding private experiment. That experiment measured about 4% faster large growing insertion and about 4% slower large hit lookup; adoption accepts the documented tradeoff rather than claiming a universal speed improvement.

## End-to-end word count

All four paths include key construction on the same three input files, verified by SHA-256. Three fresh processes per path/input/backend compare every complete output dictionary with Python Counter. Pipeline time includes file loading and counting; output and verification follow timing. RSS is process peak immediately after counting, in MiB.

| Input / path | Baseline ms | Adopted ms | Baseline MiB | Adopted MiB |
|---|---:|---:|---:|---:|
| repeated / var | 49.683 | 49.630 | 14.156 | 14.125 |
| repeated / typed | 35.397 | 35.318 | 14.109 | 14.125 |
| repeated / add-substr | 21.747 | 21.493 | 14.109 | 14.125 |
| repeated / sub-map | 22.478 | 21.858 | 14.078 | 14.094 |
| distinct / var | 25.534 | 26.325 | 47.172 | 46.938 |
| distinct / typed | 23.125 | 23.692 | 42.156 | 42.438 |
| distinct / add-substr | 24.451 | 25.974 | 42.156 | 40.500 |
| distinct / sub-map | 10.385 | 10.515 | 28.859 | 28.875 |
| book / var | 18.337 | 18.589 | 4.422 | 4.438 |
| book / typed | 12.277 | 12.497 | 4.391 | 4.406 |
| book / add-substr | 9.230 | 8.871 | 4.391 | 4.453 |
| book / sub-map | 8.258 | 8.346 | 4.188 | 4.203 |

The apparent all-distinct add-substr slowdown did not reproduce in nine additional alternating pairs: 24.490 ms baseline versus 24.451 adopted, with identical dictionaries in all eighteen processes.

## Representative compiler translation

Both executables link the same current compiler objects to their respective paired O3 runtime. They translate the same seven current source units and current source prelude with `--no-interfaces`, separate caches, one warmup and three interleaved measured pairs. This isolates the runtime change without comparing warm interface replay to cold source parsing. It is not a full build or a new c2x2c scaling score.

| Metric | Baseline | Adopted |
|---|---:|---:|
| cpu_s | 6.886021 | 6.953032 |
| wall_s | 6.922184 | 6.997772 |
| bytes | 1821957.000000 | 1821957.000000 |

Median compiler CPU is about 1% higher. All fourteen generated C/H files are byte-identical between executables (1,821,957 bytes). The earlier compiler gains over Robin Hood remain historical evidence, not a fresh comparison in this run.

## Verification and limits

- Focused native, forced-scalar, ASan/UBSan and Rosetta x86-64 builds each pass 206 tests and 15,685 assertions, plus a two-million-operation independent dictionary oracle and full traversal/200,003-key verification.
- Checked-in coverage crosses the split threshold during foreign-Scope growth, moves a split Map and destroys its previous owner, exports a large Map and destroys its source Context, and exercises concurrent root growth across the threshold.
- All 114 primary performance samples and 28 targeted confirmation samples pass their oracles. No concurrent compiler work was observed or discarded. The compiler comparison guard also accepted its run with no outside compiler overlap.
- Desktop browser/window activity and CPU frequency are not fully controlled. Some rounds vary substantially, including native typed controls. Use the paired medians and confirmations; do not interpret small deltas as universal gains or exact instruction costs.
- `tools/gate-state.py ensure agent-pr-check` passes on the completed source and regenerated bootstrap at `81c08489fa6467760cd13d29d7c36cc0855fee73`: 1,164 tests, 103,725 assertions, 1,380 fixtures and 138 matching book outputs, plus command and bootstrap/stage checks. See the [archived adoption plan](../../../../plans/archive/grouped-map-split-storage.md). All four measured generated runtime C files are byte-identical to the final gated files.
- Full PLSO, Notes, Jackson, external-table SOTA cohorts, Linux/GCC performance and a full clean build-cost/c2x2c scaling run were not repeated for this allocation-policy adoption. Their previous reports retain their original scope.

## Local evidence

The ignored local archive `debug/grouped-split-adoption/` holds source snapshots, build commands and hashes (`build.json`), binaries, every raw sample (`samples/`), confirmations (`confirm/`), compiler outputs/results (`compiler/`), focused checks (`checks/`), and the publication gate log. A fresh clone does not contain that archive. The earlier experimental allocation diagnostics remain under `debug/grouped-rss/`.
