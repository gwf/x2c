# Integrated Pool and Channel delivery checkpoint

> Status: reference - correctness validated; all listed tradeoffs accepted.
> Current-dev baseline: `74bc688575f3702ae701639533bbe44eda6c51e7`.
> Validated and measured candidate: `a596f6cb5d9d0b7f81962e14581faa39d55debfb`.
> Gary accepted the previously reported Channel and retained-index tradeoff.
> Broader checks found additional small absolute runtime costs listed below.
> On 2026-10-30 Gary explicitly accepted the additional costs and authorized
> merging the validated candidate to dev. The index redesign remains blocked.

## Integrated result and correctness

Current dev was merged without conflicts. Its Thread cleanup syntax is retained.
The measured Pool fast path, owner counters, depot transfers, immutable index,
Channel monitor registration, and shared-condition buffering remain unchanged.
Delivery fixes add missing API prose, classify the bridge as internal, and wrap
lines to the existing source standard. They make no algorithmic change.

Independent review found no blocking correctness or contract issue in the
integrated runtime. Generated C/H and documentation were reviewed. Bootstrap
and self-host comparisons pass. `tools/gate-state.py ensure agent-pr-check`
passed, including 1,133 unit tests with 99,349 assertions, CLI/compiler probes,
documentation checks, and command checks. The first gate attempts exposed
missing API documentation and formatting; those findings are corrected.

## Measurements against current dev

Both exact committed trees passed the full performance snapshot: clean build,
stage comparisons, build scaling, shootout, runtime suites, and representative
compiler translation. Runs were serialized. Snapshot builds used the standard
snapshot configuration; no other owned workload ran concurrently.

Two complete freshly built runtime archives were linked against identical
benchmark C with `-O2 -fsigned-char -pthread`. Five alternating pairs per
configuration cover both accounting modes. There are 160 processes for the
previously failing cases and 160 for independent Channels at 1, 2, 4, and
8 pairs. Selected accounting-off medians:

| Workload | Current dev | Candidate | Elapsed change |
| --- | ---: | ---: | ---: |
| Eight independent Pools, 16M allocation/free pairs | 1392.838 ms | 45.826 ms | -96.71% |
| Eight independent rendezvous Channel pairs, 160K messages | 918.685 ms | 255.372 ms | -72.20% |
| Eight independent buffered Channel pairs, 800K messages | 344.608 ms | 47.679 ms | -86.16% |
| One-worker Pool release, 100K cycles | 316.945 ms | 316.237 ms | -0.22% |
| Local Channel, 10M round trips | 335.888 ms | 343.280 ms | +2.20% |
| Shared rendezvous Channel, eight pairs, 160K messages | 680.427 ms | 701.887 ms | +3.15% |
| Shared buffered Channel, eight pairs, 800K messages | 388.273 ms | 388.459 ms | +0.05% |

These results retain the independent-resource gains. They do not erase earlier
reproduced shared-buffering slowdowns. The index still retains superseded
arrays until shutdown; no reclamation or global lookup mutex was introduced.

## Compiler and build checkpoint

The snapshot's build cost score increased from 55.2822 to 55.5379 (+0.46%).
Sequential build CPU increased from 38.9117 to 39.2016 seconds (+0.75%), while
authored source lines increased 0.28%. Stage-three build elapsed was 21.1486
versus 21.0558 seconds. This one snapshot pair does not establish a reproducible
build-cost regression.

Snapshot stage-zero translation was initially 3.82% slower, while stage one
was 0.59% slower. A matched confirmation checked both converged compilers:
both report a nonempty prelude and no missing interfaces. The same seven
representative source files have identical contents in both trees. Five
alternating pairs for each stage used `/usr/bin/time -l` to record whole-process
instructions/cycles and a common external wall timer. The 140 measured
translations followed warmup. Summed seven-source medians:

| Stage | Dev elapsed | Candidate elapsed | Dev instructions | Candidate instructions |
| --- | ---: | ---: | ---: | ---: |
| 0 | 1.8800 s | 1.8571 s | 29,852,184,123 | 29,356,206,389 |
| 1 | 1.8729 s | 1.8520 s | 29,870,259,087 | 29,375,968,154 |

Instructions decrease about 1.65% and elapsed decreases 1.1-1.2%. The initial
translation slowdown did not reproduce. This covers representative translation,
not an assertion that every compiler workload or complete build is faster.
The snapshot shootout aggregate x2c/C ratio changed by +0.38%; the ported/C
ratio changed by -3.37%. These are ratios to pinned C calibration, not matched
full-application improvement claims.

## Additional runtime costs discovered before publication

The broad snapshot exposed positive timing deltas outside Channel. Five
alternating pairs of the existing native benchmark executables then checked
those workloads. Units below are nanoseconds per measured operation, as defined
by each benchmark's elapsed/count calculation.

| Operation | Snapshot dev | Snapshot candidate | Confirmation dev | Confirmation candidate | Confirmation change |
| --- | ---: | ---: | ---: | ---: | ---: |
| Buffer indent, width 80 | 5.532 | 6.093 | 5.583 | 6.402 | +14.67% |
| Scanner decimal number | 5.687 | 5.875 | 5.543 | 6.180 | +11.49% |
| String concat | 13.230 | 13.640 | 13.835 | 14.705 | +6.29% |
| String join | 33.760 | 34.325 | 33.085 | 34.995 | +5.77% |
| Split iterator try-next | 15.018 | 15.515 | 14.787 | 15.896 | +7.50% |
| Short repeated file line | 60.150 | 63.200 | 54.700 | 55.450 | +1.37% |

Buffer indentation is the clearest repeated separation: every confirmation
candidate sample exceeds every baseline sample. Decimal scanning and String
join are slower in all five paired confirmations. The other results have more
overlap and variability. Several larger gains also appear in the same suites,
including Pool allocation/free, Scope allocation/free, and iterator operations.
Those gains do not silently waive these costs.

The generated C and native object files for Block, Buffer, Scan, String, and
Iter are byte-identical between these trees. The Buffer, Scan, and String
benchmark C is also identical. Linked layout changes: for example, scan_number
moves from offset 0x2dd5c to 0x2e478, while Buffer_indent remains at 0x4958.
This rules out changed instructions in those module objects, not all indirect
effects. Code/data placement, allocation history, and host effects are possible
explanations; their causal contributions have not been isolated. No layout
tuning or further runtime design change was attempted.

## Evidence and delivery boundary

Under `.context/lock-contention/`:

- `delivery-performance/`: complete baseline/candidate snapshots, raw suite
  outputs, toolchain/machine receipts, and build-cost records.
- `delivery-bench/metadata.json`: exact runtime revisions, archives, harness,
  executable hashes, and native flags.
- `measurements/delivery-current-dev/` and `delivery-channel-scaling/`:
  320 alternating runtime processes and summaries.
- `delivery-compiler/`: prelude checks, source identities, 140 time/counter
  records, raw stderr, and aggregate summaries.
- `delivery-runtime-confirm/`: 50 alternating processes, per-operation raw
  outputs and summaries for the additional runtime costs.

Gary explicitly accepted these additional runtime costs and authorized merging
the validated candidate to dev on 2026-10-30. This closes the acceptance hold;
the final upstream/proof check still precedes publication. The replacement
index remains blocked. No unmeasured future tradeoff is authorized.
