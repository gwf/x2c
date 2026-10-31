# Results, charts, and recovery

The complete saved comparison materials live in Git on `dev`. No original
worktree, `/tmp` directory, visualization directory, or chat is required to
recover the saved results and figures.

The current public candidate is [run 20261031T170749Z](runs/20261031T170749Z/README.md),
measured from clean source revision `06a81d6535120d6c0c07e320751548075c5d3fc1` and first
published with results in `4b881e60fd9c4492cea9947a57d072d18e04b5ef`. Run identifiers use UTC.
Observation time: 2026-10-31 10:07 PDT / 2026-10-31 17:07 UTC.

It covers 76 programs, eight columns, and sixteen fresh-process samples per
program (1,216 observations). All official fixtures and local-profile output
checks passed. Summary charts use the nine problems shared by all columns.
The four available k-nucleotide programs remain in per-problem tables.

## Saved runs

| Run (UTC) | Columns | Shared problems | Use |
| --- | ---: | ---: | --- |
| [20261031T011256Z](runs/20261031T011256Z/README.md) | 4 | 10 | Historical; Python source metrics have a known comment-accounting error |
| [20261031T024309Z](runs/20261031T024309Z/README.md) | 6 | 9 | Rust/C++ adoption; corrected source metrics |
| [20261031T031704Z](runs/20261031T031704Z/README.md) | 8 | 9 | Go/Java adoption; before idiomatic source changes |
| [20261031T035446Z](runs/20261031T035446Z/README.md) | 8 | 9 | Quiet-window calibration after the first idiomatic changes |
| [20261031T134323Z](runs/20261031T134323Z/README.md) | 8 | 9 | Ordinary Node and Buffer rewrites |
| [20261031T145604Z](runs/20261031T145604Z/README.md) | 8 | 9 | Fannkuch, FASTA, and parallel trees |
| [20261031T161720Z](runs/20261031T161720Z/README.md) | 8 | 9 | Parallel spectral-norm; Counter probe rejected |
| [20261031T170749Z](runs/20261031T170749Z/README.md) | 8 | 9 | Latest: parallel fannkuch adopted; loop-bound adopted |

[runs/index.json](runs/index.json) lists immutable run paths and revisions.
Each run contains its exact report, compressed baseline, benchmark manifest,
three chart forms in SVG/PNG/PDF, CSV data, rendering source, and provenance.
The report hashes match the original chart provenance. Historical labels and
errors are retained and explained, rather than rewritten as current results.

[Evidence](evidence/README.md) preserves full calibration samples and receipts
where available, paired source experiments (including the rejected Map update),
reference-selection checks, and the unchanged-C sanity check. The first
four-column run's original full JSONL and build/check receipts were not
retained. All 480 compact sample records are recovered from its committed
baseline and report, and explicitly labeled as recovered. No missing fields
or observations were invented.

[current.json](current.json) and [current.md](current.md) are the mutable latest
report used by the harness. Immutable run copies retain previous results when
another calibration replaces those files.

## Verify and recover

From a normal clone of `dev`:

```sh
cd examples/shootout/results
shasum -a 256 -c SHA256SUMS
gzip -dc runs/20261031T170749Z/baseline.json.gz > /tmp/shootout-baseline.json
gzip -dc runs/20261031T170749Z/raw/calibration-raw.jsonl.gz > /tmp/shootout-samples.jsonl
```

`SHA256SUMS` covers the archived runs, supporting evidence, and pinned chart
requirements. Compressed files preserve their original uncompressed bytes.
Probe evidence also records original byte counts and SHA-256 values.

To recover the exact published source corpus, use the publication revision
in the selected run's README or `runs/index.json`:

```sh
git worktree add --detach /tmp/x2c-shootout-source 4b881e60fd9c4492cea9947a57d072d18e04b5ef
```

The original absolute paths in machine/build receipts are historical evidence.
They are not required locations for a new checkout. Native executables,
compiler binaries, package caches, and external toolchain installations are
not archived. Their recorded versions and hashes identify the observed build;
rebuilding on a different host need not reproduce identical native bytes or
timing. Sources, fixtures, official specifications, dependency pins, and build
instructions remain in Git at each recorded revision.

## Render saved data without benchmarking

Create an isolated plotting environment, then render the latest saved report:

```sh
python3 -m venv /tmp/x2c-shootout-charts
/tmp/x2c-shootout-charts/bin/python -m pip install -r examples/shootout/results/requirements-charts.txt
/tmp/x2c-shootout-charts/bin/python examples/shootout/results/runs/20261031T170749Z/charts/render.py examples/shootout/results/runs/20261031T170749Z/current.json /tmp/x2c-shootout-figures
```

To render the focused serial/parallel comparison from its saved samples:

```sh
/tmp/x2c-shootout-charts/bin/python examples/shootout/results/runs/20261031T145604Z/charts/render-comparison.py examples/shootout/results/evidence/parallel-trees/serial-comparison.json.gz /tmp/x2c-shootout-figures
```

The unchanged serial source is `benchmarks/binarytrees/serial.x`. Its earlier
complete reports and charts remain in the saved runs. Run `20261031T145604Z`
retains its same-compiler serial/six-worker elapsed and total CPU comparison.

To render the earlier Counter/spectral source-probe chart:

```sh
/tmp/x2c-shootout-charts/bin/python examples/shootout/results/runs/20261031T161720Z/charts/render-probes.py examples/shootout/results/evidence/counter-spectral/results-quiet.json.gz /tmp/x2c-shootout-figures
```

To render the latest loop-bound/fannkuch source-probe chart:

```sh
/tmp/x2c-shootout-charts/bin/python examples/shootout/results/runs/20261031T170749Z/charts/render-probes.py examples/shootout/results/evidence/bound-fann/results-quiet.json.gz /tmp/x2c-shootout-figures
```

The renderer creates its output directory. It reads saved measurements and
does not compile or run benchmark programs. The requirements record the
versions used for the saved figures. PDF/SVG timestamps, font availability,
and Matplotlib metadata can change output bytes when rendering again; use
checksums to verify the preserved originals, not to require identical rerenders.

To collect new timing data, follow the [suite instructions](../README.md).
Use a quiet machine, preserve the same workload and process model, and retain
raw samples and receipts before another run replaces the ignored build folder.
Do not compare different baseline identities as a longitudinal regression.

## Website integration and interpretation

[site/BENCHMARKS.md](../../../site/BENCHMARKS.md) specifies the existing Astro
asset paths, curated exports, suggested page content, and facts that must
accompany the charts. No website page or deployment is introduced by this
preservation change.

[Remaining performance gaps](remaining-gaps.md) ranks current local outcomes
and separates observed facts, tested source changes, and unmeasured candidates.

These are local measurements of selected contributed programs, not official
website timings or general language rankings. Java includes JVM startup and
JIT compilation in every fresh-process sample. C binary-trees uses parallel
workers, as do both x2c binary-trees entries. The [threading notes](threading.md)
explain the scope. Source LOC and compressed source bytes are separate metrics.
Canonical-size timing remains unrun. The recorded quiet observations establish
the pre-run window, not zero background activity throughout measurement.
