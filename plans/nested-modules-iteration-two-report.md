# Nested modules: iteration-two research report

Status: isolated private spike; full specification remains unproven.
The compiler at 99f0f4e2 regenerated all 78 runtime and 65 compiler
sources, compiled their native objects, and linked the regenerated compiler.
The seven-file macro migration also passes its focused check.
Evidence: `debug/combined-final-descriptor-current-regeneration.log`.

Repairs at 01bd3982 add completed ancestor constructor declarations, optional
package manifest values, and selected native initializer receipts for module
groups without layout metadata. The combined compiler builds successfully. Its module matrix passes 113/113;
its native-meta matrix passes 10/17. Bootstrap recovery remains pending.
The receipt fallback adds one configured preprocessing pass for each previously
unprojected module-native group.

Current bootstrap refresh, independently relocated bootstrap recovery,
fixed-point self-host comparison, and the final existing correctness gate
remain pending. Successful regeneration does not establish those results.
Do not integrate or publish the spike without explicit adoption authorization.

## Latest acceptance evidence

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
| Current compiler regeneration | 99f0f4e2, `debug/combined-final-descriptor-current-regeneration.log` | All 78 runtime and 65 compiler sources regenerate, native compile and link successfully; bootstrap recovery and fixed-point equality pending |
| Durable native-meta module controls | 01bd3982, `/tmp/x2c-module-native-meta-98tou6tr/results.json` | 10/17 pass; seven required cases fail, detailed below |
| Module matrix | 01bd3982, `/tmp/x2c-module-probes-za4z56xq/results.json` | 113/113 pass, including the repaired nested entry constructor and retained initialization |
| Layout matrix | 01bd3982, `/tmp/x2c-layouts-_55e7pvq/results.json` | 70/71 pass; only ordinary packed-provider syntax fails, also unsupported by the baseline |
| Whole-compiler exact replay | 01bd3982, `/tmp/x2c-modules-final-replay-j0rti9v3/results.json` | All 249 C/H/XI/XNM artifacts match cold/retained in each of two homes |
| Collection order and identity | 01bd3982, `debug/final-receipts-collection-order.log` and `debug/final-receipts-identity.log` | Standalone/after-module parity, relocation identity and collision controls pass |
| Reversed object order | 01bd3982, `/tmp/x2c-reversed-object-order-o426j671/results.json` | Both member-type and entry-type cases pass original/reversed object orders; initialization, cleanup and shutdown occur once |
| Package delivery | 01bd3982, `/tmp/x2c-nested-package-delivery-vrhwqble/results.json` | Canonical Make/archive, consumer, bundle, installation and relocated native-C rebuild controls pass |
| Structured bootstrap | 12942052, `debug/combined-origin-reuse-bootstrap-refresh.log` | Historical hierarchical artifact refresh compiles and links; current and independent relocated recovery pending |

The current native-meta positives that pass are `module_prerequisite`,
`nested_private_meta`, `ordinary_runtime_cycle`, `package_private_meta`,
`module_lifetime_entry_state`, and `package_public_meta_probe_alias`.
`module_cycle`, `parent_private_rejection`, and `package_private_rejection`
reject with their expected diagnostic classifications.

The complete module matrix now passes, including the nested entry constructor
and its retained initialization check. The six added ordinary-body SCC and
entry/member effect controls also pass.

The current native-meta failures are `active_ordinary_prefix`,
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

## Full specification coverage

Passing controls establish their tested cases, not an entire specification row.

| Requirement | Implemented and passing evidence | Remaining failure or unattempted evidence |
| --- | --- | --- |
| Membership, ownership and nesting | Existing module fixtures cover three levels, duplicate entries, missing members, unlisted consumers, ancestor/sibling privacy and direct members | Current matrix 113/113; comprehensive symlink/ownership-path mutation combinations unattempted |
| Static/module/public visibility | Function, type, state, macro, alias and protocol fixtures retain exact binding ownership | Full declaration/definition disagreement combinations and repeated private native-meta type spellings insufficiently exercised |
| Nested public exports and packages | Current durable package meta positives and package-private diagnostic pass; ordinary package naming/aliases/with fixtures exist | Canonical Make/archive, bundle, installation and relocated-C consumer pass; full package protocol/native-module/foreign-name filtering unattempted |
| Prefix/suffix effects and ordered producers | Lisp, alias, declaration-producer, sibling include and direct-member parity fixtures exist; real macro recipes regenerate compiler | Current reached ordinary prefixes and direct-member native state fail; general readiness contract remains unproven |
| Declaration collection and scheduling | Collection supplies authoritative registry; Tarjan orders provider body work; seed plus current provider limits retained contexts; full compiler regenerates | This is not SCC-driven declaration collection. Seed binds first; actual producer prerequisites remain separate |
| Native headers, layouts and hidden support | Target preprocessing selects namespace and complete-family demands; private aliases and opaque completion repairs implemented | Current layout matrix 70/71; arbitrary pragmas, header-injected semantic fields and fully conditional semantic layout remain unproven |
| Shared objects, initialization and cleanup | Existing runtime shared-object fixtures and historical reversed-link controls pass; current native entry lifetime passes | Current native initialized state/cleanup/direct-member cases fail; corrected direct native cycle rejects, while the indirect-call cycle is missed |
| Cache equivalence and invalidation | Whole-65 exact replay passes at 01bd in two homes; membership/preamble/nearer-header mutation fixtures check outcomes | Complete 01bd replay passes; invalidated-versus-fresh full artifact/binding equality is not established by outcome-only mutation tests |
| Generated outputs and bootstrap | Seven-file macro migration and current full compiler regeneration pass; historical hierarchical bootstrap refresh works | Current bootstrap refresh, independent relocated recovery, fixed-point equality and final correctness gate pending |
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

These counts use committed source 01bd3982 and the exact starting dev baseline.
The authored comparison excludes generated `src/linked-meta.x` from both trees.
No generated bootstrap artifacts contribute to these source counts.

| Source corpus | Files | Lines | Bytes |
| --- | ---: | ---: | ---: |
| Baseline authored compiler | 54 | 52,413 | 1,963,433 |
| Current authored compiler | 64 | 56,461 | 2,124,330 |
| Baseline tracked compiler .x, including linked-meta.x | 55 | 53,225 | 1,994,997 |
| Current tracked compiler .x, including linked-meta.x | 65 | 57,273 | 2,155,894 |
| Baseline macro implementation | 1 | 5,461 | 209,276 |
| Current seven-file macro implementation | 7 | 5,543 | 211,361 |

Current authored compiler source adds 4,048 lines and 160,897 bytes versus
the starting tree. These totals include the complete experimental implementation;
they do not measure nesting alone. Record:
`.context/component-scheduling/final-source-size.json` in the scheduling worker.

## Latest projection work-count evidence


The same generated outer.c, clang flags, and dependencies compile successfully
before and after per-extraction canonical-origin reuse. Both outputs have SHA256
6ba6704be6af0f779a78be42821880bb6083ab7ee66f6d4f5af6fd99c5fc4c4f.
Path.resolve calls fall from 17,548 to 482. Both versions retain two CPP passes,
four metadata reads, two extraction calls, and 684,165 extracted bytes.
Receipt: /tmp/x2c-origin-reuse-pvcop9hl/results.json.
This partial workload measures repeated work, not elapsed time or full-build
throughput. The hot host prevents a useful comparative timing claim.

## Recommendation

Revise and keep isolated. Current native state, readiness and cycle failures
remain material. Bootstrap recovery, final correctness validation and final
matched cost evidence are also incomplete. These results reject the tested
implementation paths; they do not establish that nested modules are impossible.
Any later adoption requires explicit authorization.
