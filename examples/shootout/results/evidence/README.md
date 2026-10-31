# Supporting evidence

This directory preserves results that previously lived only in ignored build
folders or `/tmp`. Files ending in `.gz` decompress to the original bytes.
They are evidence, not commands executed by the website or publication gate.

## Calibration evidence

Each `../runs/<run>/raw/` directory holds the available raw calibration and
build/check receipts. JSONL records contain every measured observation;
receipts include compiler versions, commands, source/binary hashes, input and
output checks, CPU times, RSS, environment facts, and measurement methodology.
The latest run also retains its one-off quiet-window wrapper and CPU samples.

The first four-column run only has compact samples recovered from committed
reports. Its missing original full JSONL and build/check receipts are explicitly
recorded in the run README. Later runs retain original full calibration files.

## Paired source experiments

`paired-probes/` retains 192 completed measurements: four workloads, two input
sizes, two versions, and twelve samples each. It includes baseline and variant
sources, generated C/headers, diffs, scripts, commands, toolchain hashes,
input files, output checks, results, report, and logs. The interrupted earlier
attempt is retained separately and excluded from final statistics.

`paired-probes/manifest.json` maps original relative paths to compressed
archive paths, byte counts, and original SHA-256 values. For example:

```sh
gzip -dc examples/shootout/results/evidence/paired-probes/RESULTS.md.gz
```

The original report predates publication and says no changes were landed.
Subsequently, the n-body pair precomputation, FASTA Buffer reuse, and regex JIT
changes were published at `68156a1c6`. The full quiet-window run then measured
those sources at `20261031T035446Z`.

The additive Map update experiment was not adopted. It regressed approximately
20-21 percent at both sizes and lost every alternating pair. Its explanation
about generic numeric dispatch is a hypothesis, not profiled attribution.
This rejects that source substitution, not every possible Map optimization.

The paired experiments used an active desktop. They are not the later quiet
calibration, and the five-times-larger inputs are not the canonical profile.
Original scripts expect their old temporary checkout layout and copied build
artifacts. Recover source revisions and adapt local paths to reproduce the
experiment; do not execute historical scripts as a current build interface.
Native binaries and external library/toolchain caches are omitted; original
artifact hashes are retained. Compressed `.x` and generated `.c` files are inert
historical evidence, not additional benchmark entries or compiler fixtures.

## Reference admission and C compatibility

`reference-adoption/` retains Rust/C++/Go/Java source-selection checks, rejected
k-nucleotide candidates, and verified Go toolchain download metadata.
The [coverage report](../reference-coverage.md) explains those exclusions,
plus the earlier Rust/C++ findings. Exact contribution bytes, source paths,
hashes, fixtures, and specifications remain pinned in `benchmarks.json` at
each publication revision.

`c-through-x2c/` retains the unchanged-C sanity report and available command
logs. All ten sources passed the native C build driver; seven also passed
x2c parsing, emitted-C compilation, and output parity. FASTA, k-nucleotide,
and reverse-complement parser failures were not repaired or hidden. See the
[annotated report](../c-through-x2c.md).

These raw receipts contain historical machine paths and process information.
Preserve them for audit; publish curated chart/data exports on the website.
