# Regex-redux profiling and source-size audit: 20261101T204543Z

Measured clean source: `fed582d496606c11eb09e4a817f7fa9ddf2a2464` after integrating dev `4fffeabec82ffd6335934beb205330988e7382d0` and rebuilding. Baseline program source: `36c17924d0c8980c57aa1e9cd661e5c9d5ac3caf`. Both sides of final paired comparisons use the same integrated compiler/runtime and -O2/-DNDEBUG program flags. Foreign sources and calibration `53fdc5b1230c52ce` remain pinned; foreign timings were not repeated.

## Result

Tuned regex-redux now uses one native PCRE2 JIT match stream per literal substitution and alternates two typed scratch buffers through the five ordered replacements. It also strips headers/newlines into typed storage, caches native handles outside match loops, and avoids sizing scans and canonical intermediate Strings. Each count worker retains private native match state and reads the fixed caller-owned sequence through joins. Only the six prescribed consuming patterns use the specialized helper; other negative native results raise rather than silently producing partial replacements. The general package API is unchanged.

| FASTA input units | Before ms | After ms | After / before | Paired wins |
|---|---:|---:|---:|---:|
| 1000 | 2.475 | 2.383 | 0.963x | 11/12 |
| 6500 | 5.133 | 4.443 | 0.866x | 12/12 |
| 6600 | 3.674 | 2.878 | 0.783x | 12/12 |
| 100000 | 24.490 | 12.059 | 0.492x | 12/12 |
| 1000000 | 220.580 | 98.205 | 0.445x | 12/12 |

At the larger input, median peak RSS changes from 69.16 MB to 53.62 MB. The final comparison checks ten output cases and retains 120 fresh timings. Eighty fixed-seed generated cases separately exercise replacement growth, shrinkage, all prescribed literals, count patterns, headers and line endings. Every compared output byte matches.

## Phase investigation and alternatives

Diagnostic instrumentation of the fixed pre-integration toolchain records eight samples at each of three sizes. At local input, median inside-program elapsed time was about 22.91 ms: read 0.49 ms, strip 1.09 ms, count launch 0.08 ms, substitution chain 21.13 ms, join/print 0.03 ms. Across stripping and replacements, native sizing scans used about 8.75 ms, output scans 11.08 ms, and String canonicalization 2.26 ms. Those phase medians overlap and must not be added as independent wall-time components. Worker match timings are sums of worker elapsed intervals, not CPU time or extra critical-path time.

An instrumented scratch candidate reduced the observed local replacement chain to about 10.0 ms. These diagnostic phase runs encountered desktop/build activity and are not acceptance speedup measurements. Uninstrumented alternating pairs in monitored windows establish the accepted gains. The archived exact profiled sources distinguish those temporary probes from the final helper and error check.

A generic single-pass Regexp.substitute probe avoided the preliminary sizing call when the output fit. In its clean fixed-toolchain comparison, local elapsed improved 25.14 -> 20.52 ms, but retained capacity increased memory and the scratch variant was substantially faster. The package experiment is not adopted; its source and raw screening/clean data remain archived. This rejects that allocation policy for this campaign, not every possible generic wrapper improvement. Caching native handles in the scratch candidate separately improved the larger fixed-toolchain case 106.66 -> 98.87 ms.

## Source-size audit and cleanup

An independent tokenizer reproduced all LOC and normalized gzip counts for all 75 admitted programs at the baseline revision, with zero mismatches. It covers both x2c variants, C, Rust, C++, Go, Java and Python, and explicitly handles the C++ raw string found in this corpus. Independent counting also reproduces all 75 final measured sources. Both scripts and per-source hashes/counts are archived.

The chart did not show C shorter by physical code lines overall: baseline tuned x2c used 0.950x C lines, but 1.142x normalized gzip bytes. LOC counts nonblank lines after comment removal. Gzip compresses comment-free source with outside-literal whitespace collapsed at level 1. Names, token choices, repetition and library/compiler notation affect compressed size; it is not a count of concepts. Both measures exclude imported libraries and generated code.

Pidigits contained nine private Integer forwarders around GMP operations. Both programs now keep the same five mpz_t fields directly in the existing Spigot owner and call GMP there. Both extracts, operation order, init/clear order and final partial-line padding remain. Idiomatic LOC changes 79 -> 61 and gzip 900 -> 678 bytes; tuned LOC changes 81 -> 59 and gzip 917 -> 676 bytes. Integrated local twelve-pair timings are effectively flat: idiomatic 268.423 -> 269.494 ms and tuned 257.047 -> 257.627 ms. No speedup is claimed for this cleanup.

Explicit Thread scheduling and the separately measured spectral serial kernels explain other source costs. The earlier shared spectral kernel regressed smaller cases; it is retained rather than shortened for the score. The tuned regex helper adds source to express its specialized replacement path; the result is measured rather than hidden from the size chart.

Current shared-workload geometric means: tuned elapsed is 1.110x C and 0.946x Rust. Tuned source uses 0.953x C lines and 1.142x C normalized gzip bytes. These compare selected programs, not general language rankings.

## Evidence and limits

- [Full table](current.md), [paired summary](comparison/summary.json), [updated chart](charts/runtime-source-size.png).
- `raw/` retains the final full twenty-program run: twelve fresh observations per program after one warmup, plus original build/check receipts.
- `comparison/` retains integrated paired data, independent audit, phase samples, generated checks, monitoring, and reproducible scripts. Pre-integration screens are labeled separately; early contaminated windows are not acceptance evidence. Original before/final native binaries remain in ignored local debug storage.
- `sources/` retains old/new sources, intermediate candidates and package/profiling experiments. `charts/` retains SVG/PNG/PDF, CSV, renderer and environment versions.

The other agent completed its gate before the monitored acceptance windows. The monitor records a ten-second clear window and process snapshots throughout accepted comparisons and the full update, with no detected outside compiler. Ordinary desktop activity remained, and snapshots cannot prove zero interference. Canonical-size timings and foreign recalibration remain unrun. Publication validation is recorded in the completed plan. No new recurring gate was introduced.

## Publication fixture repair

The first publication gate exposed an intermittent symbol-fixture filter bug.
The filter appended a following multiline symbol key to the prior value when
Map iteration put them next to one another. A deterministic inert dump
reproduces the exact failure. The existing filter now recognizes the next
top-level expression boundary. All 16 symbol fixtures pass with unchanged
expectations. No compiler output, language behavior or recurring check changed.
The reproduction is archived; full failed logs remain in local debug storage.
