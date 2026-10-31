# Saved chart forms

The summary scatter, per-implementation star profiles and runtime/LOC box plots
use the same eight shared problems and all eight series. There are 64 shared
marks and 75 rows in measurements.csv. The scatter uses geometric means;
star centres use arithmetic means. Boxes show variation across problems,
not confidence intervals over timing samples. LOC and compressed bytes differ.

The separate three-idiomatic-probes figure plots elapsed and total CPU medians
with interquartile bands across tested input sizes. Each source/input has 12
fresh-process observations. Its CPU metric sums worker user/system time.
Both Thread cutoffs and the batched-serial control remain visible. This is
separate from the full calibration's 56 samples per program.

```sh
python render.py ../current.json /tmp/shootout-figures
python render-probes.py /tmp/recovered-three-probes /tmp/shootout-figures
```

Use ../../../requirements-charts.txt in an isolated environment. All PNG/SVG/PDF,
CSV and provenance originals are checksum-covered. See [run notes](../README.md).
