# Run 20261031T145604Z

Published report revision: `9d070d9a0cf2c13dbebf339f4c708fcbd7354439`.
Measured source revision: `e44721497e0004c921ccacec098f330bd2248726`.

This local-profile run measures Array bulk copying in fannkuch-redux, Choice
records in FASTA, and ordinary Thread batches in binary-trees. All 76 official
fixture and local-output checks pass. Sixteen fresh-process samples per program yield 1,216 observations.
The summary cohort is the same nine problems across all eight columns.

`current.json` is the exact chart input; its hash matches chart provenance.
`baseline.json.gz`, `benchmarks.json`, and `raw/` retain the original baseline,
inputs, source hashes, full samples, build/check receipts, and quiet observations.
Timing began after six consecutive ten-second CPU samples were at least 90
percent idle. This records the pre-run window, not zero background activity
throughout measurement. Native binaries and external caches are not archived.
Recover exact sources from the publication revision and follow the parent
[recovery guide](../../../README.md).

`charts/` contains PNG/SVG/PDF, CSVs, renderer, comparison, and provenance.
`website.json` is the curated public export; machine-path receipts are audit
records rather than website assets. Java includes JVM startup and JIT in every
sample. Canonical-size timing remains unrun.

## Changed idiomatic entries: separate-run comparison

Compare with run `20261031T134323Z`. Values are median elapsed milliseconds; these
full runs are not an alternating causal experiment. C reference drift is shown.

| Problem | Before ms | After ms | C before ms | C after ms | Before/C | After/C |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fannkuchredux | 55.580 | 48.507 | 15.044 | 15.397 | 3.69 | 3.15 |
| fasta | 29.272 | 20.625 | 8.043 | 8.244 | 3.64 | 2.50 |
| binarytrees | 109.685 | 25.650 | 23.845 | 23.824 | 4.60 | 1.08 |

Fannkuch uses `working.setslice(0, n, permutation)` to copy into the existing,
separate working Array. FASTA builds an ordinary Array of Choice objects,
precomputes cumulative probabilities once, and reads letter/probability fields
during sampling. Alphabet order, cumulative addition order, random-number
steps, seed continuity, and output wrapping are preserved. Neither change uses
typed containers, SubStrings, raw storage, or a custom allocator. Binary-trees
uses ordinary Thread batches in both x2c columns, with one worker per depth.
The unchanged serial.x and a same-compiler quiet serial/parallel comparison
retain the serial baseline and expose both elapsed and total CPU time.

The separate active-desktop alternating probes won all twelve pairs for each
workload/size. FASTA matches the old source and contributed C at eleven sizes;
fannkuch matches both at three sizes. These probes are preliminary evidence,
separate from this full quiet calibration. The original sources, scripts,
results, and source diff are in `../../../evidence/fann-fasta/`.

The adopted C binary-trees entry uses pthread workers. Both x2c binary-trees
entries now use parallel depth batches. These are selected programs with mixed
execution modes;
see the [threading explanation](../../../threading.md).

## Same-compiler quiet serial/parallel binary-trees comparison

Depth 14 uses sixteen alternating fresh-process pairs and one warmup per source.
The six-worker and serial versions allocate identical full Node trees.

| Mode | Median elapsed ms | Median total CPU ms |
| --- | ---: | ---: |
| serial | 107.544 | 107.111 |
| parallel | 25.534 | 119.674 |

`binarytrees-serial-parallel` supplies PNG/SVG/PDF and CSV. Its renderer and
provenance accompany the figures. All 32 samples and both sources remain in
the parallel-trees evidence directory.
