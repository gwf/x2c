# Benchmarks Game website integration

The recoverable source of truth is
[examples/shootout/results/README.md](../examples/shootout/results/README.md).
All saved chart sets, reports, samples, recipes, and supporting experiments are
versioned there. The latest public candidate is run `20261031T145604Z`.
This document prepares integration; it does not add a page, alter site builds,
or deploy the website.

## Assets and data

Use one run consistently. For the latest candidate, its directory is:

`examples/shootout/results/runs/20261031T145604Z/`

- `charts/runtime-source-size.svg`: summary plot; PNG and PDF also available.
- `charts/implementation-profiles.svg`: individual problem outcomes.
- `charts/runtime-loc-distributions.svg`: distributions across problems.
- `charts/measurements.csv`, `charts/summaries.csv`, and `charts/comparison.csv`:
  downloadable values used by those figures.
- `website.json`: curated portable metadata and measurements, excluding host
  paths and process listings. CSV-derived numbers retain string representation;
  convert them to numbers if building interactive charts.
- `current.md`: complete per-problem tables, including unavailable cells.
- `current.json`: full audit report; prefer `website.json` for public ingestion.

For a future Astro page, copy the chosen SVG/PNG files, CSVs, and `website.json`
into `site/public/benchmarks/20261031T145604Z/`. Astro copies `public/` assets
into the static output. Keep the archive authoritative; do not hand-edit
numbers in a page or duplicate raw measurement logic in JavaScript. No copy
step or recurring gate is added now. A future `site/src/pages/benchmarks.astro`
can load the curated JSON or use the static figures directly.

Respect the existing site base, which defaults to `/x2c/`. In an Astro page,
build an asset URL with `import.meta.env.BASE_URL` rather than assuming `/`:

```astro
<img src={`${import.meta.env.BASE_URL}benchmarks/20261031T145604Z/runtime-source-size.svg`}
     alt="Local runtime and source size across nine shared Benchmarks Game problems" />
```

Use responsive image width and let readers open the full-size profiles. Supply
an accessible table or CSV link beside the images. Keep original PDFs as
optional downloads. Do not copy `raw/`, machine receipts, process snapshots,
or original path-bearing `charts/provenance.json` directly into public assets.
The curated export includes source and publication revisions for attribution.

## Content that must accompany the comparison

- These are local selected-program measurements, not results published or
  accepted by the Benchmarks Game, and not a general language ranking.
- Name all eight columns: C, idiomatic x2c, tuned x2c, Python, Rust, C++, Go,
  and Java. x2c columns follow the [suite definitions](../examples/shootout/README.md).
- State Apple M4 Max, local profile, sixteen samples, fresh processes, exact
  measured revision, run ID, and observation time. Run IDs use UTC; the latest
  observation was 2026-10-31 07:56 PDT / 2026-10-31 14:56 UTC.
- Java includes JVM startup and JIT compilation. A separate process warmup
  does not warm the measured JVM. Do not describe it as steady-state Java.
- Summary charts use the same nine problems in every column. Per-problem
  tables cover all ten. Rust/C++/Go/Java k-nucleotide cells are N/A, with
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

The latest charts also include `binarytrees-serial-parallel` in PNG/SVG/PDF and
CSV, with a separate renderer/provenance file. Use this focused elapsed/CPU
comparison to explain the change. Retain the earlier serial chart sets.
