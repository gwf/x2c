# Figures for 20261031T181939Z

All eight series use the same eight shared problems. Per-problem CSV includes
all 75 admitted outcomes; no missing cell is treated as zero. Summary scatter
uses geometric means of per-problem minima; star centres use arithmetic means;
box plots show variation across problems, not timing confidence intervals.
LOC and compressed source bytes are separate metrics. Fresh-JVM startup/JIT
is included. All three forms preserve the established comparison style.

`reference-audit-probes` shows the separate eight-round quiet local experiment,
including candidates retained or rejected after confirmation. Its CSV gives
absolute before/candidate medians, CPU time, ratios and sample counts. Source
and command evidence lives under `../../../evidence/reference-profile/`.
The full calibration has 56 samples/program, not8. Canonical timing is unrun.

Render using the isolated dependencies in `../../../requirements-charts.txt`:

```sh
python render.py ../current.json /tmp/shootout-figures
python render-probes.py /tmp/recovered-reference-probes --output /tmp/shootout-figures
```

See [run provenance](../README.md) and `provenance.json`.
