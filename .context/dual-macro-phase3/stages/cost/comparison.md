# Exact control comparison (no timing)

Compared `/tmp/x2c-dual-compiler-baseline` with
`dual-macro-match-probe/x2c/builds/0/x2c` on identical absolute sources from
`agent-dual-transport/x2c`. 46 lexical-try fixtures plus seven compiler files
and exception-hot-paths in default/live modes: 62 translations.
Baseline:54 successful,8 expected negatives. Candidate:40 successful,
22 failures (the same8negativefixtures plus14compiler/tokenizer translations).
All8negative fixtures have checked-in compile-status1.

54 cases differ in outcome or generated C/H bytes. No normalization:
38 successful fixture outputs differ, exception benchmark2 differ, and14
compiler/tokenizer outcomes differ. Raw defer-try-cleanup C changes include
`seq{` instead `{`, additional empty statements, and absolute instead of
relative X2CErrorSite filenames. Native build reproduces undeclared `seq`
and downstream missing `parameter`; debug/phase3-control-native-check.log.
Compiler corpus fails at error-macros.xmacro `def error.nonreturning.causes`,
with bad-state operation def why inherited. Those failures need separate
isolation; this one candidate does not reject the template design.

No timing samples were collected for a candidate that fails correctness.
Collector, exact manifests, and exact-comparison.json record reproducibility.
A repaired candidate must first rerun identical paths and byte comparison.
The compiler-translation timing group follows the actual seven-file script;
exception-hot-paths is a separate group. Translation timing is not runtime
exception performance. Bound-hole control still does not prove open free
references, compiler-wide rewrite parity, or production performance.

## Corrected control with explicit common home

Supersedes the earlier candidate outcome above. Fixed statement/seq shape
candidate SHA256 `4bf027ab03ed688735092e3a20c9afcdf530a741d66800953706abe4b8a6a72a`.
Both processes explicitly receive X2C_HOME pointing to agent-dual-transport.
The inherited-def and broad path drift failures disappear: all 62 outcomes
match, and59 cases C/H outputs match raw bytes, including all 16 benchmark cases.
Three fixture C files retain origin differences: c-body-directive raise
lines 103/113 become 0; catch-filter-runtime-init line 22 becomes 0;
literal-string-positions lines 27/29 become 0. These error-site filenames also
become absolute. No normalization is applied. common-*-manifest.json and
common-comparison.json record exact outputs. Remaining origin differences
block the requested full parity criterion before paired timing.

## Final origin repair and paired measurement

Supersedes the remaining origin gap above. Candidate SHA256
`134b9bfa1a55283b9871a79d63b2a3292c2d32a8a93004de0ab146f5963b792e`
now matches all 62 cases in outcome and raw C/H bytes. The owner strips
only definition-template at m-origin wrappers before substitution; bound
slot source markers survive. Five alternating paired samples completed
with identical final timed artifacts; paired-summary.json and
paired-samples.json record results. Seven-file translation medians default
6.113 -> 6.146 seconds (+0.54%), live 7.501 -> 7.496 (-0.07%).
Exception translation medians default 0.591 -> 0.589 (-0.37%),
live 0.652 -> 0.679 (+4.25%), with overlapping noisy ranges. This is the
bound-hole try control, not full slot/effect implementation or runtime cost.
