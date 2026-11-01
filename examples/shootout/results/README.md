# Results, charts, and recovery

The complete saved comparison materials live in Git on `dev`. No original
worktree, `/tmp` directory, visualization directory, or chat is required to
recover the saved results and figures.

The current comparison is [run 20261101T204543Z](runs/20261101T204543Z/README.md),
measured from clean source `fed582d496606c11eb09e4a817f7fa9ddf2a2464` after
integrating current dev and rebuilding. Both x2c columns were rebuilt and
measured with twelve fresh processes per program: 240 observations over ten
problems. Official fixtures and local outputs pass. Foreign calibration stays
pinned; its programs were not remeasured.

Tuned regex-redux now alternates two typed scratch buffers instead of running
sizing scans and interning each intermediate substitution. The integrated
old/new comparison improves local elapsed time from 24.490 to 12.059 ms and
larger input from 220.580 to 98.205 ms. Source cleanup removes pidigits' private
Integer forwarding layer without changing its algorithm, cleanup or output.
Its paired local timings remain flat.

Across eight shared workloads, tuned elapsed-time geometric means are 1.11x C
and 0.95x Rust. The independent [source-size audit](runs/20261101T204543Z/comparison/source-size-audit.md)
reproduces all 75 admitted programs' LOC and normalized gzip counts on both
old and new trees. Tuned has fewer lines than C overall, but more compressed
bytes. The audit separates redundant wrappers from explicit scheduling and
measured kernel specialization. These compare selected programs, not general
language rankings. All three chart forms remain in SVG/PNG/PDF with CSV,
rendering source, profiling and paired evidence.

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
| [20261031T170749Z](runs/20261031T170749Z/README.md) | 8 | 9 | Parallel fannkuch adopted; loop-bound adopted |
| [20261031T181939Z](runs/20261031T181939Z/README.md) | 8 | 8 | Reference audit and parallel k-nucleotide |
| [20261031T211435Z](runs/20261031T211435Z/README.md) | 8 | 8 | Full calibration: parallel idiomatic regex/Mandelbrot and reverse Buffer |
| [20261101T154144Z](runs/20261101T154144Z/README.md) | 8 | 8 | Tuned scheduling/buffering parity; fresh x2c, pinned foreign measurements |
| [20261101T161913Z](runs/20261101T161913Z/README.md) | 8 | 8 | Tuned reverse-complement, FASTA and N-body improvements; pinned foreign measurements |
| [20261101T204543Z](runs/20261101T204543Z/README.md) | 8 | 8 | Tuned regex scratch buffers, pidigits cleanup and independently verified source sizes |

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
gzip -dc runs/20261031T211435Z/baseline.json.gz > /tmp/shootout-baseline.json
gzip -dc runs/20261031T211435Z/raw/calibration-raw.jsonl.gz > /tmp/shootout-samples.jsonl
```

`SHA256SUMS` covers the archived runs, supporting evidence, and pinned chart
requirements. Compressed files preserve their original uncompressed bytes.
Probe evidence also records original byte counts and SHA-256 values.

To recover the exact published source corpus, use the publication revision
in the selected run's README or `runs/index.json`:

```sh
git worktree add --detach /tmp/x2c-shootout-source 9c8fbbe8bc2976c1e85db7e6259a847e91671374
```

The original absolute paths in machine/build receipts are historical evidence.
They are not required locations for a new checkout. Native executables,
compiler binaries, package caches, and external toolchain installations are
not archived. Their recorded versions and hashes identify the observed build;
rebuilding on a different host need not reproduce identical native bytes or
timing. Sources, fixtures, official specifications, dependency pins, and build
instructions remain in Git at each recorded revision.

## Render saved data without benchmarking

Use the latest run's recorded plotting environment:

```sh
python3.14 -m venv /tmp/x2c-shootout-charts
/tmp/x2c-shootout-charts/bin/python -m pip install -r examples/shootout/results/runs/20261101T204543Z/charts/requirements.txt
/tmp/x2c-shootout-charts/bin/python examples/shootout/results/runs/20261101T204543Z/charts/render.py examples/shootout/results/runs/20261101T204543Z/current.json /tmp/x2c-shootout-figures
```

The per-run `render-environment.json` records the versions actually used.
Earlier cohorts retain their own provenance and the root pinned chart setup.

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

To render the earlier loop-bound/fannkuch source-probe chart:

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

## Reference audit evidence

`evidence/reference-profile/` mirrors all 70 attempted candidate configurations,
with exact source bytes, commands, diagnostics, outputs, quiet confirmation,
selection decisions, statistical k-nucleotide stacks/input and unchanged-C
sanity observations. It includes rejected attempts. Decompress the four probe
JSON/JSONL files into a temporary directory to rerender the focused chart.
No executable path stored in a receipt needs to exist for rendering.

## Three idiomatic source probes

`evidence/three-idiomatic/` preserves all seven sources, generated C, command
receipts, 142 correctness cases, 372 quiet observations, active-machine initial
screen, inputs and Docker restoration evidence, including rejected attempts.
Decompress the four focused-probe inputs described in
[run 20261031T211435Z](runs/20261031T211435Z/README.md) to render without executing benchmarks.
