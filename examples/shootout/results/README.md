# Current benchmark results

[Score history](history.md) | [Full results table](current.md) | [Structured data](current.json) | [Summary chart](charts/runtime-source-size.svg) | [Per-problem profiles](charts/implementation-profiles.svg) | [Runtime and source-size distributions](charts/runtime-loc-distributions.svg)

![Runtime and source size](charts/runtime-source-size.png)

## Latest published measurement

Run **20261101T204543Z**, measured on **2026-11-01 UTC**, uses the local
Apple M4 Max profile. All twenty x2c programs were checked and measured with
twelve fresh processes each after one warmup. The source revision is
`fed582d496606c11eb09e4a817f7fa9ddf2a2464`. These results measure that revision.

Across the eight shared problems, tuned x2c takes **1.11x C elapsed time**
and **0.95x Rust elapsed time**, using geometric means of matched workload
ratios. Foreign measurements remain pinned to calibration
`53fdc5b1230c52ce`; they were not rerun with x2c. These are comparisons of
selected programs, not general language rankings. Java includes fresh-JVM
startup and JIT compilation. Canonical-size timings remain unrun.

The tuned regex-redux comparison improves local elapsed time from
24.490 to 12.059 ms, with identical output. Typed scratch buffers remove
repeated sizing scans and intermediate String interning. Pidigits removes its
private Integer forwarding layer with flat elapsed time. Independent audits
reproduce the source-size counts: tuned uses 0.953x C source lines but
1.142x C normalized gzip bytes across the shared cohort.

## Files in this snapshot

This directory holds the promoted snapshot: the report, all three charts in
PNG/SVG/PDF, plotted measurements and summaries in CSV, and chart provenance.
[Score history](history.md) retains compact headline ratios from published
runs, with [structured history](history.json) for all language scores,
cohorts and calibration identities. The provenance report path is relative,
so the snapshot works in any checkout.

- [Summary PDF](charts/runtime-source-size.pdf)
- [Measurements CSV](charts/measurements.csv) and [summary CSV](charts/summaries.csv)
- [Chart provenance](charts/provenance.json), including the report SHA-256
- [Original run archive, profiles, raw samples and source audits](https://github.com/gwf/x2c/tree/a9aeff5b843878fd102b31402a522d2f0a1d2d6c/examples/shootout/results/runs/20261101T204543Z)


## Refresh the promoted snapshot

`make shoot-run` records scratch measurements under ignored
`examples/build/shootout/`. It leaves this published snapshot intact.
`make shoot-update` promotes the new report to `current.json` and `current.md`
in this directory and retains its summary scores in `history.json` and
`history.md`. Previous score rows remain when the current report is replaced.
Scratch build cleanup does not remove these files.

Render the promoted report without running benchmarks:

```sh
python3 examples/shootout/tools/render-charts.py \
  examples/shootout/results/current.json \
  examples/shootout/results/charts
```

The optional plotting dependencies are pinned in
[requirements-charts.txt](../tools/requirements-charts.txt). Keep the existing
single renderer; do not copy it into each saved result directory.

After an update, regenerate the figures and commit the report and charts
together. Check that `charts/provenance.json` names the same run ID and
report SHA-256. The [suite guide](../README.md) describes measurement,
calibration and reference coverage.
