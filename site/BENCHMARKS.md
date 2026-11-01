# Benchmarks Game website integration

The recoverable source of truth is
[examples/shootout/results/README.md](../examples/shootout/results/README.md).
All saved chart sets, reports, samples, recipes, and supporting experiments are
versioned there. The latest public candidate is run `20261031T211435Z`.
This document prepares integration; it does not add a page, alter site builds,
or deploy the website.

## Assets and data

Use one run consistently. For the latest candidate, its directory is:

`examples/shootout/results/runs/20261031T211435Z/`

- `charts/runtime-source-size.svg`: summary plot; PNG and PDF also available.
- `charts/implementation-profiles.svg`: individual problem outcomes.
- `charts/runtime-loc-distributions.svg`: distributions across problems.
- `charts/measurements.csv`, `charts/summaries.csv`, and `charts/three-idiomatic-probes.csv`:
  downloadable values used by those figures.
- `website.json`: curated portable metadata and measurements, excluding host
  paths and process listings. CSV-derived numbers retain string representation;
  convert them to numbers if building interactive charts.
- `current.md`: complete per-problem tables, including unavailable cells.
- `current.json`: full audit report; prefer `website.json` for public ingestion.

For a future Astro page, copy the chosen SVG/PNG files, CSVs, and `website.json`
into `site/public/benchmarks/20261031T211435Z/`. Astro copies `public/` assets
into the static output. Keep the archive authoritative; do not hand-edit
numbers in a page or duplicate raw measurement logic in JavaScript. No copy
step or recurring gate is added now. A future `site/src/pages/benchmarks.astro`
can load the curated JSON or use the static figures directly.

Respect the existing site base, which defaults to `/x2c/`. In an Astro page,
build an asset URL with `import.meta.env.BASE_URL` rather than assuming `/`:

```astro
<img src={`${import.meta.env.BASE_URL}benchmarks/20261031T211435Z/runtime-source-size.svg`}
     alt="Local runtime and source size across eight shared Benchmarks Game problems" />
```

Use responsive image width and let readers open the full-size profiles. Supply
an accessible table or CSV link beside the images. Keep original PDFs as
optional downloads. Do not copy `raw/`, machine receipts, process snapshots,
or original path-bearing `charts/provenance.json` directly into public assets.
The curated export includes source and publication revisions for attribution.

## Parallelism policy

Keep the existing idiomatic/tuned distinction and eight-column comparison.
Where official submissions for a problem use parallelism, x2c may use it too.
Where none do, keep x2c serial. Continue to honor each official workload's
algorithm and work requirements. Do not split the headline charts into serial
and parallel regimes or impose a separate matching-core comparison. The
[threading notes](../examples/shootout/results/threading.md) record the current
precedents. Earlier serial/probe charts remain historical supporting evidence.

## Content that must accompany the comparison

- These are local selected-program measurements, not results published or
  accepted by the Benchmarks Game, and not a general language ranking.
- Name all eight columns: C, idiomatic x2c, tuned x2c, Python, Rust, C++, Go,
  and Java. x2c columns follow the [suite definitions](../examples/shootout/README.md).
- State Apple M4 Max, local profile, 56 samples, fresh processes, exact
  measured revision, run ID, and observation time. Run IDs use UTC; the latest
  observation was 2026-10-31 14:14 PDT / 2026-10-31 21:14 UTC.
- Java includes JVM startup and JIT compilation. A separate process warmup
  does not warm the measured JVM. Do not describe it as steady-state Java.
- Summary charts use the same eight problems in every column. Per-problem
  tables cover all ten. Rust/C++/Go/Java k-nucleotide and Python binary-trees
  cells are N/A, with
  [recorded reasons](../examples/shootout/results/reference-coverage.md).
- Explain per-problem normalization against the fastest/shortest/smallest
  selected program, geometric means in summary scatters, arithmetic centres
  in star plots, and variation across problems in box plots. The box plots
  are not confidence intervals over timing samples.
- Distinguish LOC from compressed source size. The historical four-column
  chart has a known Python source-metric error and must not be promoted as
  the current comparison.
- Algorithms, dependencies, memory representation, and threading affect the
  comparison. C and both x2c binary-trees columns use parallel depth batches.
  Keep the
  mixed execution-mode annotation on figures and link the
  [threading explanation](../examples/shootout/results/threading.md). Do not attribute every
  gap to language overhead or compare program versions as controlled trials.
- The observed quiet window preceded measurement; zero background activity
  throughout the run was not established. Canonical-size timing is unrun.
- Link exact source/specification attribution through
  [THIRD_PARTY.md](../examples/shootout/THIRD_PARTY.md) and each run's manifest.

A useful page starts with the scope and process model, shows the summary
scatter, then the full per-problem table, profiles, and box plots. Separate
[remaining opportunities](../examples/shootout/results/remaining-gaps.md) from
measured changes. Provide run/data/source downloads and the recovery guide.

When a page is implemented, use the existing `make site-check` and local visual
review described in [site/README.md](README.md). No new check is required by
this documentation change, and public deployment remains a separate action.

The latest run includes `three-idiomatic-probes` in PNG/SVG/PDF/CSV, with
renderer and provenance. It compares elapsed and total user/system CPU time
for the separate 12-round controlled source experiment. The full report uses
56 samples per program. State the regex cleaned-byte cutoff, bounded
Mandelbrot row batches, Buffer-preserving reverse-complement boundary, and
unchanged tuned/reference sources. Docker was temporarily paused with explicit
authorization and restored after measurement; do not turn that one-off host
operation into a site build step or recurring requirement. Earlier experiments
remain labeled by their original runs. Canonical-size timing is unrun.
