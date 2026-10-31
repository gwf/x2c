# Run 20261031T161720Z

Published report revision: `d30286d20c4cd89c65d5d68f1bff8efe639e53df`.
Measured source revision: `a8d02959e25f6517cdcf189d386c637f587f016e`.

This local-profile run measures ordinary row-batch threading in idiomatic
spectral-norm. Counter objects remain a rejected source experiment; the
k-nucleotide entry retains its previous numeric Map values. All 76 official
fixture and local-output checks pass. Sixteen fresh-process samples per program
yield 1,216 observations. The common chart cohort remains nine problems across
all eight columns. Java includes fresh-JVM startup and JIT compilation.
Canonical-size timing remains unrun.

Timing began after six consecutive ten-second observations at least 90 percent
CPU idle. This establishes the pre-run window, not zero background activity
throughout timing. Exact samples, build/check receipts, source hashes, manifest,
baseline, and quiet evidence are retained in `raw/`, `benchmarks.json`, and
`baseline.json.gz`. Native executables and external toolchains are not archived.
The parent [recovery guide](../../../README.md) describes rebuilding sources and
rendering saved results without the original checkout or temporary directories.

## Separate full-run comparison

Comparison with `20261031T145604Z` uses median elapsed milliseconds. These are separate
full runs, not an alternating causal experiment; C reference drift is shown.

| Workload | Previous idiomatic ms | New idiomatic ms | C before ms | C after ms | Before/C | After/C |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| spectralnorm | 74.236 | 17.591 | 7.119 | 7.139 | 10.43 | 2.46 |
| knucleotide | 171.022 | 168.942 | 18.846 | 18.502 | 9.07 | 9.13 |

The spectral entry uses ordinary Array vectors and Rows objects. Six ordinary
Threads calculate disjoint output row blocks at N>=256. The caller joins every
worker before the next matrix product. Each row retains its original summation
order. Below N=256, the same row calculation runs serially to avoid thread
startup overhead. Tuned spectral-norm retains its existing serial typed Arrays.
The benchmark change introduces no custom allocator, raw collection storage,
or compiler/runtime edits.
Earlier serial sources and complete runs remain immutable in the prior archive.

## Quiet paired source experiments

Each size uses sixteen alternating fresh-process pairs with one warmup per
program. The probe sources, compiler/runtime/binary hashes, all 224 samples,
input/oracle outputs, build recipes, and quiet observations are retained in
`../../../evidence/counter-spectral/`. Active-desktop observations remain separate. The paired probes used compiler
revision `424a35a9e`; this full run uses the newer measured revision above.
Each before/after probe pair uses the same compiler and runtime.

| Experiment | Input N | Before elapsed ms | Candidate elapsed ms | Before CPU ms | Candidate CPU ms | Candidate wins / 16 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| knucleotide | 20000 | 40.955 | 46.551 | 40.480 | 46.111 | 0 |
| knucleotide | 100000 | 166.104 | 162.857 | 165.524 | 162.278 | 9 |
| spectralnorm | 100 | 4.100 | 4.171 | 3.808 | 3.875 | 5 |
| spectralnorm | 200 | 12.627 | 12.529 | 12.351 | 12.262 | 11 |
| spectralnorm | 256 | 19.991 | 8.387 | 19.699 | 31.633 | 16 |
| spectralnorm | 500 | 73.528 | 17.641 | 73.209 | 86.304 | 16 |
| spectralnorm | 1000 | 289.640 | 55.753 | 289.246 | 309.258 | 16 |

The Counter implementation preserves growing hash tables and output ordering.
Its additional object per distinct key did not establish a repeatable overall
benefit, so it was not adopted. This rejects this implementation, not all
possible Map improvements. The earlier rejected `counts[key] += 1` experiment
also remains preserved.

`charts/` retains all three eight-column chart forms and a focused source-probe
comparison in PNG/SVG/PDF, with CSV, renderers and provenance. `website.json` is
the portable public export; path-bearing raw receipts remain audit materials.
The previous binary-trees serial/parallel comparison is retained in run
`20261031T145604Z`; it is not relabeled as a new measurement here.
