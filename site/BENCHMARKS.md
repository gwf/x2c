# Benchmarks Game website integration

This document describes a future benchmark page. It does not add a page,
change site builds, or deploy the website. The
[suite README](../examples/shootout/README.md) owns current workload,
parallelism, calibration, and measurement instructions.

## Select one report

Use one run consistently. `make shoot-update` promotes the selected run to
ignored `examples/build/shootout/results/current.json` and `current.md`.
The JSON records source identities, host, profile, sample count, run ID,
calibration identity, per-problem results, and the shared summary cohort.
Historical reports and chart sets remain in the
[pre-cleanup archive](https://github.com/gwf/x2c/blob/b46aa0e12ab1e4356bd6b4942f1fc30ade5faff6/examples/shootout/results/README.md).

Render an existing report without running benchmarks:

```sh
python3 examples/shootout/tools/render-charts.py \
  examples/build/shootout/results/current.json \
  examples/build/shootout/results/charts
```

Optional renderer dependencies are pinned in
[requirements-charts.txt](../examples/shootout/tools/requirements-charts.txt).
The renderer writes summary, profile, and distribution figures in PNG, SVG,
and PDF, plus measurements, summaries, and provenance. Its labels describe
the selected report; a chart does not establish a new measurement.

For a future Astro page, copy selected figures and portable data into
`site/public/benchmarks/<run-id>/`. Exclude machine paths, process listings,
and private receipts from public data. Keep the original report and its
identity beside the selected source evidence. Do not hand-edit values in the
page or duplicate measurement logic in JavaScript.

Respect `import.meta.env.BASE_URL` when constructing asset URLs. Use
responsive images, an accessible data table or CSV download, and links to
full-size figures. Keep PDFs as optional downloads.

## Explain the comparison

- These are local selected-program measurements, not results published or
  accepted by the Benchmarks Game, and not a general language ranking.
- Name the eight columns: C, idiomatic x2c, tuned x2c, Python, Rust, C++, Go,
  and Java. Use the suite's existing idiomatic/tuned definitions.
- Read the machine, profile, sample count, revisions, run ID, and observation
  time from the chosen report. Identify its reference calibration separately.
- Java includes JVM startup and JIT compilation. A separate process warmup
  does not warm the measured JVM.
- Use the report's shared problem cohort for summary charts. Per-problem
  tables retain unavailable cells and the suite's exclusion reasons.
- Explain normalization against each problem's fastest, shortest, or smallest
  admitted program. Summary scatters use geometric means; profile centres use
  arithmetic means. Box plots describe variation across problems, not timing
  confidence intervals.
- Distinguish source lines from compressed source size. Algorithms,
  dependencies, representations, and threading affect the comparison. Use the
  suite's workload-specific parallelism policy; do not add serial/parallel
  headline categories or attribute every difference to language overhead.
- State measured scope and evidence limits from that run. A quiet-window
  observation does not establish zero background work throughout measurement.
- Link specifications and source attribution through
  [THIRD_PARTY.md](../examples/shootout/THIRD_PARTY.md) and the chosen manifest.

A useful page starts with scope and process model, then shows summary charts,
the complete per-problem table, profiles, and distributions. Keep proposed
improvements separate from measured results. Provide data and source downloads.

When a page is implemented, use the existing `make site-check` and local
visual review described in [site/README.md](README.md). Public deployment
remains a separate action.
