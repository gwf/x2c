# Profile regex-redux and audit source size

> Status: done - 2026-11-01.
> Measurements use clean integrated source `fed582d49`; publication gate passes
> at `26aa308c3` after the focused fixture-filter repair.

## Result and choices

Profile input, stripping, count compilation/matching, ordered substitutions,
joining and canonicalization. Compare proposed improvements with frozen current
binaries on identical local and larger inputs. Keep public library semantics,
foreign sources, workload definitions and output fixed. Audit physical source
lines and normalized gzip bytes independently; do not golf source to improve a
score or remove previously measured spectral specialization.

## Implementation and validation

1. Freeze original sources, binaries and commands. Temporary instrumentation
   records phase elapsed times separately from uninstrumented acceptance runs.
   Evaluate a generic single-pass wrapper, then typed scratch buffers with
   native PCRE2 matching for the six consuming, literal replacement patterns.
2. Keep count workers private and the input fixed until joins. Alternate two
   scratch buffers for replacements; preserve errors distinct from no-match.
   Remove pidigits' private Integer forwarding layer inside its existing
   Spigot owner, retaining both extracts, arithmetic, cleanup and padding.
3. Check official, tiny, threshold, growing-output and generated replacement
   cases. Compare twelve alternating fresh-process pairs on a quiet host;
   retain raw CPU/RSS data and reject contaminated timing windows.
4. Review the completed diff, commit the candidate and rerun all twenty x2c
   programs against pinned foreign timings. Archive sources, audit evidence,
   profiling, paired samples and refreshed charts. Integrate current dev,
   run the existing publication gate and publish.

## Design review

The generic wrapper probe reduces scans but increases retained allocation.
Keep it unadopted if the typed scratch version wins with less memory. The
benchmark helper is intentionally limited to its six fixed consuming patterns
and literal replacements; it does not replace the general Regexp API.
Substring views require canonical String owners, so native byte spans over
existing typed Block storage express the actual scratch lifetime directly.
No new allocator, package API, library rule or recurring check is needed.

## Publication finding

The initial gate exposed an intermittent existing symbol-fixture normalizer
bug: a multiline following key was appended to a selected value depending on
Map iteration order. An inert raw dump reproduces the failure. A six-line
filter boundary correction passes all 16 symbol fixtures without changing
expectations or compiler output. The required gate is repeated after this
focused repair; failed logs are retained under the campaign debug directory.

## Delivered evidence

The final integrated twelve-pair comparison improves tuned regex-redux from
24.490 to 12.059 ms at local input and from 220.580 to 98.205 ms at larger
input. Larger-input peak RSS falls from 69.16 to 53.62 MB. Both paired outputs
and 80 generated replacement/count cases match. A generic wrapper experiment
remains unadopted; the package source is byte-identical to the original.

Both pidigits variants remove the Integer layer while retaining Spigot
ownership, both extracts, init/clear order and padding. Local paired timings
are flat. Independent audits reproduce all 75 old and all 75 final LOC/gzip
counts; the chart's source-size distinction is explained in the report.

The final full run `20261101T204543Z` checks all twenty x2c programs and records
240 observations. Across eight shared workloads, tuned elapsed time is 1.110x C
and 0.946x Rust. The [immutable archive](https://github.com/gwf/x2c/blob/b46aa0e12ab1e4356bd6b4942f1fc30ade5faff6/examples/shootout/results/runs/20261101T204543Z/README.md)
retains phase data, accepted/rejected probes, source snapshots, CPU/RSS data,
quiet monitoring, source audits, CSV and all three figures in SVG/PNG/PDF.
All 1,544 archive checksums and five harness tests pass.

The publication gate passes: 1,164 unit tests and 103,729 assertions, 1,383
compiler fixtures, 138 matching book outputs, command checks and generated
stage comparisons. No authored compiler/runtime/bootstrap delta remains.
The fixture normalizer repair retains all checked-in expectations. Final
Markdown closeout reuses the valid compiler proof with doc-check.

Canonical-size comparisons and foreign recalibration were not run. Earlier
contaminated screens remain labeled separately; accepted comparisons wait for
a clear monitored window. Desktop activity and intervals between snapshots
remain limitations. No spectral kernel or further Map change was attempted.
