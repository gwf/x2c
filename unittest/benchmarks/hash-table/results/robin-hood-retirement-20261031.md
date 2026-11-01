# Shared grouped Map storage: Robin Hood retirement

Measured source candidate: `258290d238af4ba5a37e28b6d81b65672c9680e9`.
The final source tree reverts a later prefetch experiment. One subsequent export-boundary correction publishes pointers from the staged table, preserving the allocation, cleanup, and transfer order. Measured lookup/update/growth code is unchanged.

Var Map, typed Maps, and ordinary PoolTable now use one grouped storage generator. The runtime Robin Hood generator and duplicate typed update generator are deleted. The process-root Pool retains its existing append-only atomic linear index; it never used Robin Hood.

## Paired integer workloads

Both backends use O3/DNDEBUG without LTO, the same driver, and the same 80-million-input counting and mixed streams. The control is the previous adopted runtime: grouped typed Maps, Robin Hood Var Map and Pool. The candidate replaces Map/Pool and their generator consumers in that same runtime. Each row is the median of three fresh processes in rotated order. All eleven checkpoint sizes and checksums match.

| Container / workload | Control ns/input | Grouped ns/input | Grouped / control |
|---|---:|---:|---:|
| var / count | 82.3 | 83.7 | 1.017x |
| var / mixed | 62.7 | 46.9 | 0.748x |
| typed / count | 19.5 | 19.4 | 0.995x |
| typed / mixed | 26.6 | 26.7 | 1.004x |

Var Map uses about 13% less CPU across these two workloads, using an equal-weight geometric mean. Counting is approximately flat; mixed insertion/deletion improves about 25%. Typed integer results are approximately unchanged. This paired check does not refresh the 24-table SOTA ranking.

## End-to-end word count

All four paths include key construction on the same three byte-identical inputs. Three fresh processes per path/input/backend verify every output key and count against Python Counter. Pipeline time includes reading and counting; output and verification follow timing. Memory is process peak RSS immediately after counting.

| Input / path | Control ms | Grouped ms | Control MiB | Grouped MiB |
|---|---:|---:|---:|---:|
| repeated / var | 50.608 | 50.314 | 14.094 | 14.109 |
| repeated / typed | 35.387 | 35.113 | 14.109 | 14.109 |
| repeated / add-substr | 21.365 | 21.279 | 14.109 | 14.109 |
| repeated / sub-map | 22.373 | 22.268 | 14.094 | 14.078 |
| distinct / var | 25.991 | 25.838 | 41.266 | 47.172 |
| distinct / typed | 22.603 | 23.518 | 39.312 | 42.156 |
| distinct / add-substr | 24.179 | 25.100 | 39.312 | 42.156 |
| distinct / sub-map | 9.922 | 10.147 | 28.875 | 28.859 |
| book / var | 19.089 | 18.410 | 4.406 | 4.422 |
| book / typed | 12.395 | 12.450 | 4.375 | 4.391 |
| book / add-substr | 8.779 | 8.622 | 4.375 | 4.391 |
| book / sub-map | 8.327 | 8.252 | 4.203 | 4.188 |

Var word count improves about 1%, 1%, and 4% on repeated, all-distinct, and book input. All-distinct typed String paths take about 4% longer in this run. Those paths also use Pool, so sharing the backend does not imply that every complete workload improves.

## Memory cost

Var buckets retain 16-byte key/value records. Full 32-bit hashes sit beside one-byte controls in the existing hash Block. The bucket payload changes from 20 to 21 bytes, excluding headers and the padded-control/deleted-count trailer. Pool buckets change from 12 to 13 bytes. Rebuilds reuse full hashes, preserving custom hash callback behavior.

At 16,649,205 distinct integer keys and capacity 33,554,432, a separate allocation diagnostic records live bytes of 671,103,136 for Robin Hood and 704,658,684 for grouped storage: 5.0% more. Peak managed bytes are 1,006,647,552 and 1,056,980,320, also 5.0% more.

Observed process RSS grows much more: approximately 1.076 GB to 1.408 GB in that diagnostic. macOS malloc retains freed growth buffers. A private post-measurement pressure-relief probe reduces resident memory to about 681 MB and 722 MB. Production code does not call pressure relief or change the allocator. The paired counting workload reports adjusted peak memory of 1074.1 MB versus 1406.5 MB; mixed reports 537.2 MB versus 714.5 MB. This RSS cost remains real for callers.

## Compiler and verification

Seven representative source units use the same current source prelude, `--no-interfaces`, separate caches, one warmup and five interleaved pairs. Median compiler CPU is 7.841 s for the previous executable and 6.813 s for grouped storage, about 13% less. Elapsed medians are 7.861 s and 6.830 s. Both produce 1,821,957 bytes. These are source-prelude translation measurements, not full builds or warm-interface scores.

The paired campaign completes 114 samples with no compiler-overlap discards. Guards exclude concurrent compiler work. Desktop background load is not fully controlled; a later rejected prefetch experiment ran while macOS media indexing was active. Treat small elapsed-time differences cautiously.

Focused verification passes in native, forced scalar, ASan/UBSan, and Rosetta x86-64 modes. Each mode runs 205 tests and 15,676 assertions, plus a two-million-operation differential Map check. Tests cover growth, tombstone cleanup, hash callbacks, failed retry hashing, precomputed hashes, ownership, Pool/Context, and threading. Linux/GCC was not tested in this task.

A later candidate cached hash-array pointers and prefetched the candidate record. Its paired counting result regressed from 85.9 to 91.8 ns/input. That candidate was reverted. The failed experiment does not reject other future probe improvements.

`tools/gate-state.py ensure agent-pr-check` passes on `027c1f2b253c2ea5ad5c4c090b432e7dcc56282e`: 1,163 tests, 103,716 assertions, 1,380 compiler fixtures, 138 matching book outputs, command checks and bootstrap/stage comparisons. The [archived retirement plan](../../../../plans/archive/retire-robin-hood-map.md) records delivery. PLSO, Notes, the full Jackson profiles, and the complete external-table cohort were not rerun for this retirement. Their previous full-suite report remains historical evidence.

Raw sources, binaries, all samples, compiler logs, and memory diagnostics remain in the local ignored `debug/retire-robin-hood/` archive. The accepted campaign is under `performance/samples-before-probe-cache/`; its compiler results are under `performance/compiler-before-probe-cache/`. A fresh clone does not contain this local archive.
