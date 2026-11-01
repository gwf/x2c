# Profile regex-redux and audit source size

> Status: active - 2026-11-01.
> Baseline `36c17924d`; source experiments and focused checks precede acceptance.

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
