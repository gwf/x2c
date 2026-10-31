# Run 20261031T134323Z

Published report revision: `427ee5b3c4176f4bc2dec90fae149bcc68279ea3`.
Measured source revision: `d7c7787c7d1c608f86730b1ba5be3f22722c0299`.

This local-profile run measures the ordinary Node binary-trees entry and fused
Buffer reverse-complement entry. All 76 official fixture and local-output checks
pass. Sixteen fresh-process samples per program yield 1,216 observations. The
summary cohort is the same nine problems across all eight columns.

`current.json` is the exact chart input; its hash matches chart provenance.
`baseline.json.gz`, `benchmarks.json`, and `raw/` retain the original baseline,
inputs, source hashes, full samples, build/check receipts, and quiet observations.
Timing began after six consecutive ten-second CPU samples were at least 90
percent idle. This records the pre-run window, not zero background activity
throughout measurement. Native binaries and external caches are not archived.
Recover exact sources from the publication revision and follow the parent
[recovery guide](../../README.md).

`charts/` contains PNG/SVG/PDF, CSVs, renderer, comparison, and provenance.
`website.json` is the curated public export; machine-path receipts are audit
records rather than website assets. Java includes JVM startup and JIT in every
sample. Canonical-size timing remains unrun.

## Changed idiomatic entries: separate-run comparison

Compare with run `20261031T035446Z`. Values are median elapsed milliseconds; these
full runs are not an alternating causal experiment. C reference drift is shown.

| Problem | Before ms | After ms | C before ms | C after ms | Before/C | After/C |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| binarytrees | 401.320 | 109.685 | 24.308 | 23.845 | 16.51 | 4.60 |
| revcomp | 85.082 | 11.490 | 1.487 | 1.484 | 57.22 | 7.74 |

Binary-trees now uses the existing ordinary heap Node implementation, including
allocation of every leaf and the same Scope lifetimes. No typed containers,
SubStrings, raw collection storage, or custom allocator was introduced.
Reverse-complement traverses backward once, folds ASCII case, applies the IUPAC
complement switch, and emits reusable 60-character Buffer lines. It also skips
empty stripped fragments, fixing the previous blank-sequence-line bad-arg.
47 reverse-complement cases pass an independent oracle, with old-source parity
except the two cases reproducing that old blank-line failure. Eight positive
tree depths match an independent node-count oracle and the tuned/C programs.

The source diff, oracle, inputs/expected outputs, and correctness receipts are
preserved in `../../evidence/node-buffer/`. Raw native C timings still include
its parallel tree workers; the Node representation does not add parallelism.
