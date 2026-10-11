# Nested modules: iteration-two research report

Status: paused private spike; full specification remains unproven.
See the [implementation and integration handoff](nested-modules-integration-handoff.md)
and [saved evidence](nested-modules-evidence/README.md) for the paused checkpoint.
The latest native-meta matrix is 11/17 at 73c791df. Six cases remain failures.
The refreshed bootstrap built; subsequent clean compiler recovery was interrupted
at Gary's request. Final self-host comparison and the complete gate did not finish.
Starting revision: c09d9a917f4ab1afc072b3fb2ece71e7bb2a6e04.
The combined compiler at 74836bfc completed bootstrap refresh and clean
recovery. Bootstrap and stage zero match across 340 generated C, header and
native-layout metadata files. Stage zero and strict stage one also match.
Evidence: `debug/final-private-gate-second-attempt.log`.

The complete correctness gate has not passed. Subsequent checks found native
header readiness and cleanup-lowering regressions in CLI reuse and book output.
Bounded repairs are integrated; validation stopped when the spike was paused. The gate also
found authored source formatting violations; baseline allowances are unchanged.
The focused CLI translation-reuse control now passes its six cold/retained
include-selection steps after the header readiness repair. Full verification
is still pending.
All 102 book output samples also pass after the cleanup and meta-state repairs.
The first atomicity failure was an obsolete interface-version expectation.
Its focused rerun passes after the expectation changed from 11 to 15.

Independent relocated bootstrap recovery and matched native artifact costs
remain pending. The feature matrices below precede these integration repairs.
The private GitHub backup is authorized. Integration and publication to dev/main
require explicit adoption authorization.

## Earlier acceptance evidence (01bd3982)

The completed serial batch is pinned to source
01bd39829b9b66c800bfee74bd14a07808dd0b21 and compiler SHA256
17c1c11782aaf31d674cb76d131f546ce2b0ba51ae078f4ec3df29ac380c4958.
Its ledger is `.context/nested-modules/iteration-two/final-receipts-fixtures.json`.
The compiler hash remained unchanged throughout the batch.
The subsequent 256f67a7 review fix excludes executable project-meta advertisements
from completed-ancestor signature imports. Final bootstrap validation follows
that fix and the frontend forward declaration. The complete matrices below
precede these small source-review fixes. The nine-file API translation batch
passes with the forward declaration; documentation regeneration honors JOBS1.
This source repair does not prove general SCC declaration collection.

| Workload | Latest completed evidence | Result and limit |
| --- | --- | --- |
| Current compiler regeneration | 99f0f4e2, `debug/combined-final-descriptor-current-regeneration.log` | All 78 runtime and 65 compiler sources regenerate, native compile and link successfully; later combined bootstrap recovery and fixed-point equality pass |
| Durable native-meta module controls | 01bd3982, `/tmp/x2c-module-native-meta-98tou6tr/results.json` | 10/17 pass; seven required cases fail, detailed below |
| Module matrix | 01bd3982, `/tmp/x2c-module-probes-za4z56xq/results.json` | 113/113 pass, including the repaired nested entry constructor and retained initialization |
| Layout matrix | 01bd3982, `/tmp/x2c-layouts-_55e7pvq/results.json` | 70/71 pass; only ordinary packed-provider syntax fails, also unsupported by the baseline |
| Whole-compiler exact replay | 01bd3982, `/tmp/x2c-modules-final-replay-j0rti9v3/results.json` | All 249 C/H/XI/XNM artifacts match cold/retained in each of two homes |
| Collection order and identity | 01bd3982, `debug/final-receipts-collection-order.log` and `debug/final-receipts-identity.log` | Standalone/after-module parity, relocation identity and collision controls pass |
| Reversed object order | 01bd3982, `/tmp/x2c-reversed-object-order-o426j671/results.json` | Both member-type and entry-type cases pass original/reversed object orders; initialization, cleanup and shutdown occur once |
| Package delivery | 01bd3982, `/tmp/x2c-nested-package-delivery-vrhwqble/results.json` | Canonical Make/archive, consumer, bundle, installation and relocated native-C rebuild controls pass |
| Structured bootstrap | 12942052, `debug/combined-origin-reuse-bootstrap-refresh.log` | Historical hierarchical artifact refresh compiles and links; combined recovery now passes; independent relocated recovery pending |

At 01bd3982, the native-meta positives that pass are `module_prerequisite`,
`nested_private_meta`, `ordinary_runtime_cycle`, `package_private_meta`,
`module_lifetime_entry_state`, and `package_public_meta_probe_alias`.
`module_cycle`, `parent_private_rejection`, and `package_private_rejection`
reject with their expected diagnostic classifications.

The complete module matrix now passes, including the nested entry constructor
and its retained initialization check. The six added ordinary-body SCC and
entry/member effect controls also pass.

At 01bd3982, the native-meta failures are `active_ordinary_prefix`,
`active_reached_ordinary_prefix`, `module_ordinary_shared_variable`,
`module_ordinary_cleanup`, `module_meta_shared_variable`, and
`module_lifetime_direct_state`. They fail during build.
`module_initializer_cycle` incorrectly builds successfully.
`module_direct_initializer_cycle` now rejects with the required diagnostic.
Its corrected entry uses extern declarations rather than additional tentative
definitions. The original 99f control crashed before native-provider registration;
its receipt is retained separately.
These results prevent a native readiness, state or cycle success claim.

## Implementation and historical repairs

Modules retain explicit ownership, separate package identity and file-static
privacy. Entries and members produce separate implementations. Target-native
preprocessing selects layout and initialization dependencies. Generated
metadata carries support declarations without granting language lookup access.

The compiler macro implementation now occupies seven source files, including
nested quotation members. The real compiler regeneration proves that this
migration is consumed by the experimental compiler. Canonical signature
recipes repaired the real `Logger` and loop-alias regeneration blockers.
Signature collection retains names and types without executing later bodies
or declaration producers.

Earlier failures identified borrowed Map iteration, unstable marker order,
private type identity, public opaque completion, ancestor alias binding,
class signatures, package support placement and preamble replay defects.
Their focused repairs are implemented. Current matrix receipts must determine
whether each repaired behavior passes; historical failures are not current
failure claims.

## Combined integration checks

The existing serial gate reached clean bootstrap recovery and strict stage one.
Both generated comparisons pass across 340 C/H/XNM files. Its remaining
components then exposed integration defects, rather than a bootstrap defect.

The CLI include-selection reuse control passes after ordinary provider header
preparation. The complete book-output check passes all 102 compiled samples
with matching output after cleanup isolation and binding-based meta-state naming.
Evidence: `debug/final-doc-output-object-naming.log`.

Preparing inactive module headers by parsing whole providers executed later
child producers. The guard restores the declaration-only module path.
Inactive module-header readiness remains an implementation gap.

The final native matrix is 11/17 on compiler 73c791df. Both entry and
direct-member lifetime pass after retaining borrowed meta-stub signatures.
The six remaining failures are ordinary active prefixes, ordinary module
shared state/cleanup, module meta shared state and the indirect initializer cycle.
Receipt: `/tmp/x2c-module-native-meta-mtrcpz5l/results.json`.
No native lifetime regression remains in these controls.

The final three lint violations have whitespace repairs at 436c9f71.
No baseline allowances changed; final lint verification remains pending.

## Full specification coverage

Passing controls establish their tested cases, not an entire specification row.

| Requirement | Implemented and passing evidence | Remaining failure or unattempted evidence |
| --- | --- | --- |
| Membership, ownership and nesting | Existing module fixtures cover three levels, duplicate entries, missing members, unlisted consumers, ancestor/sibling privacy and direct members | Current matrix 113/113; comprehensive symlink/ownership-path mutation combinations unattempted |
| Static/module/public visibility | Function, type, state, macro, alias and protocol fixtures retain exact binding ownership | Full declaration/definition disagreement combinations and repeated private native-meta type spellings insufficiently exercised |
| Nested public exports and packages | Current durable package meta positives and package-private diagnostic pass; ordinary package naming/aliases/with fixtures exist | Canonical Make/archive, bundle, installation and relocated-C consumer pass; full package protocol/native-module/foreign-name filtering unattempted |
| Prefix/suffix effects and ordered producers | Lisp, alias, declaration-producer, sibling include and direct-member parity fixtures exist; real macro recipes regenerate compiler | 73c ordinary reached prefixes still fail; direct-member native lifetime now passes; broader effects matrix was not rerun |
| Declaration collection and scheduling | Collection supplies authoritative registry; Tarjan orders provider body work; seed plus current provider limits retained contexts; full compiler regenerates | This is not SCC-driven declaration collection. Seed binds first; actual producer prerequisites remain separate |
| Native headers, layouts and hidden support | Target preprocessing selects namespace and complete-family demands; private aliases and opaque completion repairs implemented | Current layout matrix 70/71; arbitrary pragmas, header-injected semantic fields and fully conditional semantic layout remain unproven |
| Shared objects, initialization and cleanup | Existing runtime shared-object fixtures and historical reversed-link controls pass; current native entry lifetime passes | 73c native shared-state/cleanup cases fail; both lifetime controls pass; direct cycle rejects and indirect-call cycle is missed |
| Cache equivalence and invalidation | Whole-65 exact replay passes at 01bd in two homes; membership/preamble/nearer-header mutation fixtures check outcomes | Complete 01bd replay passes; invalidated-versus-fresh full artifact/binding equality is not established by outcome-only mutation tests |
| Generated outputs and bootstrap | Seven-file macro migration and current full compiler regeneration pass; historical hierarchical bootstrap refresh works | Earlier combined recovery and fixed-point equality pass; final recovery was interrupted; relocated recovery and final gate remain incomplete |
| Include portability | Canonical resolved dependencies and native companion metadata implemented | Macro-spelled bootstrap includes, configured-root-only native closure and other platforms insufficiently exercised |
| Cost and performance | Exact historical matched measurements retained below | Final matched native artifact sizes, whole-workload counts, quiet-host timing and peak memory unmeasured |

## Scheduling and initializer limits

The scheduler forms components from completed declaration facts and orders
body work from include and typed declaration prerequisites. Recorded
`binding-references` rows do not drive that schedule. It does not collect
declarations through a general prerequisite SCC engine. The seed binds before the remaining components.
Passing body recursion controls do not remove this specification gap.

Initializer dependency collection follows bound initializer syntax. It does
not follow arbitrary indirect function calls into bodies to discover every
object read. Therefore direct-object cycle controls do not prove general
transitive or indirect-call cycle rejection. Source owner:
`src/compiler.x`, `Compiler.initializer_references` and `_collect_references`.

## Measured cost


The first prototype was measured before scheduling changes. Gary then warned
that the host was running hot. No starting or revised wall-clock samples are
used to claim slowdown, speedup, or retained throughput.

Temporary instrumentation changed one ownership object in otherwise frozen
binaries. All six translations succeeded. These counts measure candidate
presence probes, not total filesystem operations or elapsed time.

| Matched workload | Units | First prototype probes | Early cached probes |
| --- | ---: | ---: | ---: |
| Ordinary files | 26 | 31,822 | 2,365 |
| Flat module control | 34 | 87,730 | 4,343 |
| Three-level nested control | 34 | 149,178 | 4,343 |

Raw record: `/tmp/x2c-modules-iteration-two-counts-v2/results.json`. Later
constructor, ancestry, scheduling, identity, and layout changes are outside
this count comparison. The equal-unit flat/nested pair isolates ownership
depth for this operation only; it does not explain all translation cost.

The layout size comparison translates identical diamond source graphs with
the retained recursive-render binary and the bounded family-header binary.
All six translations succeed. Header totals include generated support headers.

| Depth / unique families | Recursive C bytes | Recursive H bytes | Bounded C bytes | Bounded H bytes |
| --- | ---: | ---: | ---: | ---: |
| 2 / 5 | 7,072 | 13,044 | 3,342 | 8,584 |
| 5 / 11 | 60,370 | 118,728 | 6,876 | 19,288 |
| 8 / 17 | 483,520 | 964,116 | 10,410 | 29,992 |

Raw record: `/tmp/x2c-layout-growth-2qmqsolw/results.json`. This establishes
bounded aggregate-body duplication on those workloads, not bounded alias-prefix
work, native execution performance, or full compiler throughput.

| Historical tracked compiler .x source (includes generated linked-meta.x) | Files | Lines | Bytes |
| --- | ---: | ---: | ---: |
| Original dev baseline | 55 | 53,225 | 1,994,997 |
| First prototype | 63 | 54,457 | 2,041,253 |
| Candidate 92f62c50 | 65 | 55,389 | 2,078,120 |

At historical candidate 92f62c50, the macro implementation occupies seven
files and 5,511 lines, compared with one file and 5,461 lines originally.
That candidate has 2,164 more tracked compiler source lines than the baseline.
Source movement is not counted as new code.
Records are `.context/nested-modules/iteration-two/source-size.json`.

Comparable full native object/archive sizes, quiet-host cold/retained timing,
peak memory, parse/replay/producer attribution, and mutation rebuild receipts
remain unmeasured. A baseline directory with only runtime objects was rejected
as an invalid comparison with the candidate's compiler and runtime objects.

## Current source size

These source-only counts use 436c9f71 and the exact starting dev baseline.
The authored comparison excludes generated `src/linked-meta.x` from both trees.
The subsequent private signature-retention repair adds two authored lines.
No generated bootstrap artifacts contribute to these source counts.

| Source corpus | Files | Lines | Bytes |
| --- | ---: | ---: | ---: |
| Baseline authored compiler | 54 | 52,413 | 1,963,433 |
| Candidate authored compiler | 64 | 56,595 | 2,126,498 |
| Baseline tracked compiler, including linked-meta.x | 55 | 53,225 | 1,994,997 |
| Candidate tracked compiler, including linked-meta.x | 65 | 57,407 | 2,158,062 |
| Baseline macro implementation | 1 | 5,461 | 209,276 |
| Candidate seven-file macro implementation | 7 | 5,545 | 211,388 |

Candidate authored compiler source adds 4,182 lines and 163,065 bytes versus
the starting tree, across 35 changed authored compiler owners. These totals
include the whole experimental implementation; they do not measure nesting alone.
Record: `.context/nested-modules/iteration-two/final-source-size.json`.

## Latest projection work-count evidence


The same generated outer.c, clang flags, and dependencies compile successfully
before and after per-extraction canonical-origin reuse. Both outputs have SHA256
6ba6704be6af0f779a78be42821880bb6083ab7ee66f6d4f5af6fd99c5fc4c4f.
Path.resolve calls fall from 17,548 to 482. Both versions retain two CPP passes,
four metadata reads, two extraction calls, and 684,165 extracted bytes.
Receipt: /tmp/x2c-origin-reuse-pvcop9hl/results.json.
This partial workload measures repeated work, not elapsed time or full-build
throughput. The hot host prevents a useful comparative timing claim.

## Unmeasured nesting costs

The flat/nested ownership comparison holds declarations and file counts fixed,
but measures only candidate-path probes. The diamond comparison measures two
layout implementations. Neither is a complete nesting-cost assessment.
Authored implementation size, owner components, translated units, native artifact
sizes, retained rebuild work and cold/warm translation cost still need a matched
flat/nested comparison. Quiet-host timing and peak memory remain unmeasured.

## Recommendation

Revise and keep isolated. Current native state, readiness and cycle failures
remain material. Combined bootstrap recovery and self-host equality pass. Final correctness
validation and matched cost evidence remain incomplete. These results reject the tested
implementation paths; they do not establish that nested modules are impossible.
Any later adoption requires explicit authorization.
