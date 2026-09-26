# Source consolidation research

> Status: active
> Working local prototypes on `codex/consolidation-research`, based on
> `origin/dev` at `df3b43822d6454fa9d3e1295a53e70e9b277c212`.
> Publication is held for Gary's review. This is a research result, not a
> declaration that every original consolidation target is finished.

## Scope and preserved evidence

The input is the cleanup table on `spike/evaluator` in
`plans/native-meta-execution.md`. Its estimates remain hypotheses. This spike
implements comparable replacement prototypes for the largest targets, counts
replacement templates and glue, and separates relocation from deletion.
No finding here declares the original estimates overstated.

The earlier `6e4089e9` candidate on `codex/consolidation-first-wave` and the
artifacts in `/Users/gary/.codex/worktrees/56af/x2c/.context/campaign-patches/`
remain intact. Copies are in this checkout's `.context/previous-campaign/`.
The earlier claim that core-family sharing completes typed-family Array/Map
wrappers is corrected in `evaluator-and-source-consolidation.md`.
Its narrow compiler experiments do not reject the full lowering merger.

Initial current-dev inspection found the lowering owners, six emitter cases,
nine transaction-map copies, and separate public Array/Map wrappers still
present. Core-family instantiation was existing partial sharing, not the full
typed-family target. FNV byte/file primitives and the build state seed were
already shared, but full request-specific hash construction was not prototyped.
Recursive Match and autodiff still lived in lib. The original broad proposals
were not marked complete merely because these smaller existing pieces existed.

The two first substantial targets were all typed-family Array/Map wrappers
and shared lowering ownership. Both now have working source patches. Separate
workers used registered worktrees; root owns integration. No worker pushed,
merged dev, or ran publication gates. Functioning alternatives and actual
failed implementations are retained under `.context/campaign-patches/`.
That ignored evidence directory is workspace material; preserve the checkout
or copy it with the source patch before removing a worktree.

## Original proposal dispositions

"Implemented" below means implemented locally in the retained research tree,
not published or performance-approved. Partial rows distinguish working
subsets from the original full target. A source investigation is not a
working replacement prototype. Queued work is never counted as attempted.

| Original proposal | Disposition and exact extent |
| --- | --- |
| Unified transform/lambda/cleanup lowering | Partially investigated. All three owners merge into transform; whole-unit rounds, nested-lambda-only normalization and terminal unit cleanup traversal disappear. Function-local discovery/exit rewrites, regions, and cache-ID walks remain. The measured slowdown from local subtree iteration is corrected below. |
| Ordinary emitter syntax for try/defer/vcompound/vpostfix/vseqcall/dstrvalue | Implemented locally. All six private emitter kinds disappear in normalized output. Pre-cleanup try/defer remain legitimate lowering intermediates; complete catch skeleton construction now belongs to transform. |
| Shared top-level dispatch with skip-body continuation | Implemented locally. Full and collecting parses share classification; collection retains binding, visibility and meta facts, then skips bodies through existing operations. `skip_body` is separate from `c.shallow`. |
| SymTxn copying across all transaction state | Partially investigated. A separately preserved working draft covers all nine maps with lazy child/parent frames. Begin copies zero rows, including nested begin. Ordinary Map access still materializes a complete parent; no tombstones/read-through/merged iteration yet. Not a completed no-copy replacement. |
| Typedef-chain walkers and declaration/binding facts | Partially investigated. Two declared-type/tag drivers share one typedef step while retaining their sequencing and hop policies. The remaining drivers and declaration/binding facts have not been replaced. |
| Six adapter memo sites | Implemented locally. One existing-style Decorator macro preserves keys, early publication, cache lifetime and miss creation. |
| Ordered convert_expression rules | Partially investigated. A complete eleven-rule working alternative builds and runs; it adds 142 net lines and remains outside the retained tree. A compile-time/generated rule-list alternative is uninvestigated. |
| CLI application and package eligibility metadata | Implemented locally for simple flag/string/list application and the eligibility whitelist. Complex options retain their semantic handlers. Final wrapped source adds four net lines. This is ownership consolidation, with no deletion claim. |
| Build identity hashes | Partially investigated through source. Existing `x2c_fnv_bytes/file` and `_state_base` already share primitive and build-seed mechanics. No new complete path-construction prototype. Input paths/content, null/list delimiters, tool identity, depfiles and native preprocessor inputs remain deliberate differences. |
| Project field-table setters | Partially investigated. All eleven repetitive List fields use one field-pointer table in a translated draft, +23/-20. It is saved separately, not retained. Scalar kind/output validation remains separate; manifest runtime coverage is not established. |
| Typed-family Array/Map including public wrappers | Implemented locally. Both boxed families instantiate typed-family operations, observers and iterators; specialized Var functional/update/heap and native typed indexing boundaries remain. All template changes and opt-in publication glue are counted. The second-wave review establishes Array.try_next was already public; only Array.try_get was accidentally added, and that is removed by the second-wave compatible composition. |
| Error record storage and full value-transfer walks | Partially investigated. Retained patch uses one record Pool and shares both Error copy modes. A separate full five-path/six-entry walk prototype works, but removes only two lines after counting templates and adds Error/Logger traversal allocations. It is preserved, not integrated. |
| Error frame-chain merging | Uninvestigated; explicitly separate from record storage and transfer walks. |
| Recursive mutex mechanics and Context ownership arms | Implemented locally. Shared raw recursive-lock helpers retain per-owner once controls and allocation-free fatal boundaries. Identical Context Block/Bytes/Buffer arms fold together. |
| Recursive Match under unittest | Implemented relocation. 445 source lines move to unittest; unit differential tests and benchmark includes follow. This is not whole-repository deletion. |
| Simpler Match cache | Implemented locally as a circular LRU ring with one head. Two net production lines disappear while ordinary unpinned eviction stays constant-time. The timestamp prototype is preserved but replaced after repeated larger-capacity churn measurements found a regression. Admission, pins, generations, leases and invalidation remain. See readiness correction below. |
| Autodiff to packages | Implemented local relocation. Runtime and all macro bodies move to an importable ordinary package. The exposed multiunit path-List lifetime defect is corrected with existing retention; two fresh full translations and fresh no-interface translation pass. Final combined verification is recorded below. |
| Named small public API items | Partially investigated through source/caller inventory. No removal prototype or incompatible API retirement is retained. Detailed compatibility differences are below and in public-api-retirement.md. |
| Legacy macro body forms | Partially investigated through parser, fixtures and documented contract. No removal prototype. Both forms remain explicitly documented source compatibility; migrating callers/fixtures and changing that contract is still open. |
| Evaluator tail calls from 658fb92d, separate from 6 MB policy | Implemented local trampoline state change. Independently reproduced deep tail calls with the 1024 non-tail fence retained; no 6 MB policy is included. AUTO, source frame diagnostics and budget/reentry remain. |

## Substantial replacements and compatibility

### Typed-family Array/Map

The complete deletion target is duplicate public container operations,
observers and iterator wrappers in `array.x`, `map.x`, `typed-array.x` and
`typed-map.x`, replacing them with the typed-family templates, not merely the
already shared core algorithms. The retained worker patch has 343 production
additions and 1,076 deletions: 733 net lines removed. Templates add 99 net
lines, included in that total. Four authored fixture migrations add 18 net
lines. Subsequent integrated documentation fixes are counted in the final tree:
355 additions and 1,079 deletions across these six production files, 724 net
lines removed. The original patch's 733-line saving excludes those later edits.

Hooks preserve Var missing/void behavior, negative Array indexing, Map
null-versus-empty behavior, growth publication ordering, boxed ownership,
and native typed unchecked inline brackets. Boxed publication is opt-in to
avoid duplicate Map.map definitions. Var-only functional and heap operations
remain outside the common family. Numeric typed hot operations retain native
operators. No origin authentication or second AST validation was added.

Correction from second-wave source verification: only Array.try_get is
additive. Array.try_next exists on the original dev baseline at line 793
and its Lisp registrations must remain. A storage-qualified Type-hole attempt to privatize them failed parsing
as too many macro arguments, for both tested spellings. The actual patch and
logs remain. This rejects that implementation, not private readers: splitting
the reader template is still possible. The second-wave composition removes only the accidental checked getter and
restores the original native template interface; its final checks are recorded in the continuation below.

Native assembly caught owner String literals adding first-use interning guards
to hot methods. The correction passes numeric null owner for boxed families
and constructs diagnostic literals only on failing paths. After correction,
normalized Map_get/getdefault and MapIntInt_get/set/updateindex instructions
and relocations match baseline. Array get/set counts recover but text differs;
find/count gain one entry; Map_set changes from a two-entry tailcall to inline
logic. This is performance evidence about generated code, not timing parity.

Worker evidence: full 946 tests/20,755 assertions, four family fixtures,
focused 90 tests/5,950 assertions, and source-matched stage0/1 equality for
188 C/H files. Root independently reran all four family fixtures in the
combined tree. See `typed-family.patch`, `typed-family-report.md`, failed
private-reader patch/logs, and both hotpath-assembly JSON reports.

### Shared lowering and ordinary expression AST

The full intended replacement eliminates separate recursive lowering owners,
whole-unit and local rescan machinery, cleanup skeleton/discovery duplication,
private emitter nodes and repeated cache-ID dependency/root discovery.
The retained patch owns all three original files in transform but is only a
partial completion of that traversal/skeleton/dependency target.

Worker patch: 2,477 additions, 2,598 deletions, 121 net removed. Root also
removes the now-unused two-line c.fixed field/initialization. Approximately
2,460 lines from lambda and cleanup relocate into transform, which is separate
from net repository deletion. Adapter template glue is included in the count.

Outer mutable capture cells and capture rewriting must precede normalization
of a lambda body. A first merged version did the reverse and emitted an
undeclared target in a defer environment initializer. The actual V3 patch and
C error log are preserved; the corrected order passes lambda checks and
selfhosting. The first memo macro used a trailing Statement argument and
failed six invocations; correction uses the existing Block-first Decorator
convention. No public behavior was discarded to make either correction pass.

Retained behavior includes binding identity, declaration order, evaluate-once
protocol updates/destructuring, old/new postfix values, cleanup value saving,
defer environment lifetime, protected goto boundaries and nested transfers.
Worker stage1/2 compares 184 C/H files exactly; 200 tests/6,162 assertions
pass. Root's reviewed destructuring expectation changes replace dstrvalue
with normal block/declaration/expression AST; executable stdout/status and
warning-free C compilation match. They are intentional representation changes.

Generated baseline/candidate deltas are not authored savings: worker stable
comparison records C +15,912/-20,501, H +0/-44, and xi +92/-94. Those include
removed-file relocation and generated formatting. Checked-in bootstrap has
not been hand-edited or refreshed for this held research candidate.

`lowering-next-boundaries.md` records the complete remaining replacements:
the now-prototyped ordinary catch sites/handler/setjmp AST; fused function metadata discovery and
exit lowering; producer-local normalization closure; and both cache-key
transitive dependencies and partition-specific root collection. A narrow
one-step dispatcher or one cache traversal would not evaluate those targets.

The subsequent full try/catch patch replaces the remaining emitter skeletons
with ordinary declarations, initialization, indexing, calls and conditionals.
It includes static retained MatchCaptureSite/ErrorCatchSite registration,
volatile handlers across longjmp, capture binder declarations, detach before
arm entry, exact setjmp controlling position, and shared cleanup trailers.
The full patch with the final binding correction is +187/-166, net 21
lines added: ownership consolidation with no deletion claim. Shared
integer/declaration builders remove redundant AST helpers. An unnecessary
`.list()` failed fatal-warning selfhosting; correction removes it. A reverse
indexed-List arm loop became reverse foreach to avoid quadratic construction.
All six private emitter arms are gone.

Review found v4 freshly minted catch declaration IDs. The correction retains
producer-issued IDs and introduces ordinary catch declarations before lambda
preparation. Existing Scope cells now own escaping explicit references.
Declaration followed by assignment avoids an existing Var compound-initializer
union issue. A preliminary shadowed `context` capture failed selfhosting;
actual v5/v6/v7 patches and failure logs are preserved. Direct, shadowed,
unused, snapshot and two-column constructed catches pass native -Werror and
runtime probes. An escaped reference mutates to 18; Unit replay twice returns
18,18,19 without duplicate initialization. These tests establish cell lifetime,
not extended ownership of borrowed capture payloads: use Error.snapshot for
values retained beyond the handler. Baseline implicit snapshot capture emits
an undeclared identifier; the ordinary declaration producer also repairs that
existing defect, recorded separately from preserved behavior.

Worker final stages1/2 compare 184 C/H files exactly; 153 tests/812 assertions
pass. Ten focused fixtures cover dynamic/many-arm catches, finally transfers
and protected exits. Root owns reviewed expectation updates and combined
verification below. See full-try-final-with-bindings.patch and try-binding/.

The ordered-conversion alternative covers eleven full stages after lambda/Func
normalization, with a shared Conversion record and ordinary rule function
array. V1 added 162 net lines; V3 removes unused aliases and adds 142. It builds
with fatal warnings and runs seven focused fixtures plus 200 runtime tests.
It remains a functioning alternative patch, not an infeasibility verdict.
No performance benefit is established for its added indirect calls/state.

Fixture diff review found an actual contract regression: lowering compound
updates to ordinary calls hid their targets from `_changed_operand`, so five
try-written roots lost required volatile qualification. This is not an accepted
snapshot difference. The retained correction recognizes existing Var/native/
protocol update operations and reuses the ordinary root and alias analysis.
Its failed preliminary tuple spelling and mismatched common declarations,
original nonvolatile C, corrected patch,
and focused proof are preserved under volatile-update/. The complete
correction adds 11 net lines, including both common declarations and runtime
helper signatures. Exact baseline reproduces the discarded-qualifier warning
for a deferred Var postfix; allowing volatile optional references repairs that
existing helper limitation without casts that drop access qualification.
Function-pointer types naming these exported functions now include the volatile
pointee qualifier; tracked callers are direct, but this is an external C API
compatibility boundary to review separately from the now-corrected Array public API.
Arbitrary callee writes across longjmp remain outside this generated-update
repair; the optimized probe and baseline comparison are preserved separately.
Final combined verification is recorded below.

### Error storage versus the complete transfer experiment

The retained runtime patch is +130/-155 production lines before integrated
comment changes: 25 net removed. Only 12 of that saving comes from sharing
Error's two copy modes. One record Pool, lock mechanics and folded Context
arms supply the rest. This is not comparable scope to the 300-730-line full
transfer hypothesis. Twenty-four test lines cover record identity/lifetime.

The independent complete walk prototype covers Error ordinary snapshots and
explicit-pool recopy, Logger retention, Context immutable export, List promotion
and List.try_own. Owner-specific pooling/domain rejection, opaque/prohibited
values, Context cycles/rollback, and allocation-free in-place List publication
remain deliberate policies. V1's complete production patch is +185/-187,
including its 39-line traversal template: two net lines removed, but 43 more
than the retained runtime subset. Error/Logger gain a temporary Block per
copied List spine. This version is functioning evidence, not useful deletion
or proven performance improvement; it stays outside the integrated tree.

V2 attempts inline owner policies to remove callback/helper glue. It fails
because Statement policy arguments retain call-site identities while generated
function parameters acquire different bindings. A correction using existing
x2c.ident construction reproduces the mismatched binding in a minimal fixture.
Actual V1/V2 patches, both fixtures, emitted C/H and logs are preserved under
`full-transfer*`. A Function decorator preserving bound parameter identities,
shared leaf policy, and specialized allocation-free spine emission remain
possible next implementations. The proposal itself is not rejected.

V1 passes 947 tests/20,763 assertions and Error floor/shutdown probes;
source-matched selfhost stages1/2 compare all 184 C/H files byte-for-byte.
Frame-chain merging was not attempted or counted as part of these results.

### Full-state transaction draft

The complete target is read-through environment frames, changed-row writes,
tombstones and merged iteration across all nine transaction maps. The separate
working draft covers symbols, bindings, enumerators, macros, statics, binding
facts, counters, layouts and source definitions, preserving borrowed owner
identity, rollback, transient deletion and source metadata. It adds 66 net
production lines (+164/-98). All nine raw child maps are observed empty at
begin, including nested begins; ordinary Map boundaries still copy a parent.

Actual probe failures were private-field visibility and an improperly
initialized source-facts fixture, not evidence of transaction infeasibility.
The corrected compiler-local inert accessor and frontend-equivalent setup
are preserved separately, then removed from production. An eager facts getter
found by the probe was corrected. Source-matched stage0/1/2 equality, existing
REPL command/protocol checks and nine editor metadata tests pass. Full retained
frame patch and instrumentation evidence stay separate from root integration.

### Package relocation and evaluator

Autodiff moves 1,566 implementation lines, rather than deleting them.
The package uses ordinary package.mk archive/header/module machinery, exports
its existing macros through the entry import, and explicitly retains adnode's
Var tag. Consumers import package names; core unit tests stay in the existing
suite. The core Lisp compilation dependency disappears. No native conversion
contract was removed to bypass package failures. The working import consumer
prints `9 6 9 6`, exercising generated and runtime gradients.

The direct-C fixture harness receives optional one-argument-per-line native
flags for the migrated package consumers, preserving one C compilation and
existing warning checks. Package headers precede runtime headers and archives
follow the generated C input. A destination-conversion fixture's explicit
stack record now names the package's raw `struct autodiff__AdNode` tag, instead
of the former core tag; its compile-time/runtime stdout contract passes.

The package exposed an order-dependent native String predicate failure when
another unit follows its import. Import-only is sufficient to reproduce it;
reversed order and the other unit alone pass. Preloading before Frontend and
selecting modules earlier failed to resolve fresh runs. These actual failed
patches and cold/warm logs are retained. A native backtrace identifies the
predicate in `_native_module_suppliers`, not a broken autodiff bridge.

`select_package_module` appended canonical cells to a global List under a
persistent Scope, but the active unit Context still owned those cells. Closing
that Context allowed cells to be recycled as raw pointer values. One existing
`native_module_order.try_own()` after append retains the graph. Both wider
main.x attempts and all diagnostic scaffolding are removed. The corrected
frozen image passes the fresh two-unit reducer, two independent fresh normal
61-unit translations, and a fresh full no-interface run. A unit-header search
path correction preserves the package's namespaced public types. The earlier
warm unit executable passes 950 tests/20,785 assertions; root repeats this
on the final combined source below.

Evaluator verification uses an exact source-matched baseline binary/archive
preserved before root edits. An inert probe produces tail=call-stack,
non-tail=call-stack,recovery=10 on baseline; candidate produces tail=1,
non-tail=call-stack,recovery=10. The fence remains 1024, and AUTO remains.
Focused Lisp suites pass 104 tests/1,219 assertions. Tail pending state is
local to evaluator invocation, preserving reentry. The 6 MB E2 source policy
is separate historical evidence and is not retained: measuring displacement
from eval entry does not account for an already shallow native/pthread stack.
Its older failure claims are not presented as independently rerun results.

## Remaining compatibility decisions and coverage

ScopeStats maxima serve live REPL statistics; retiring them changes public
layout/output. Var.parse is a parser with documented conversions. List.subseq
is not identical to getslice's step/diagnostic/whole-List identity behavior.
Array.indexof is a generated alias, but removing it from every typed family
would enlarge the named retirement. Var.fallback and wide scalar operations
have live cross-unit consumers; visibility retirement does not delete their
bodies. `public-api-retirement.md` preserves the detailed caller inventory.
No incompatible retirement is silently included.

Legacy braced-arrow and parenthesized unterminated bodies have two parser
helpers and branches, plus explicit compatibility docs and fixtures. A complete
retirement must migrate valid uses and decide the now-invalid input behavior;
only source/corpus investigation has occurred. Project field-table +3 and
conversion-rule +142 drafts do not prove every table/rule representation grows.

Timing measurements are pending a quiet same-host window. Sustained unrelated
REPL/compiler work was observed in another checkout; it was not stopped.
The later host observation still records sustained XProtect and VM load.
No noisy runtime samples are called performance parity. Static assembly and
correctness/selfhost results stand separately. Match eviction, Array/Map hot
paths, compiler lowering/translation and module preload/fingerprint scope need
same-host timing before publication. No new recurring gate was introduced.

## Integrated verification and final measurements

Root rebuilt the source-matched combined compiler and its autodiff package.
It passes 950 tests/20,785 assertions and stage1/2 equality for 180 C/H files.
The complete CLI/dependency/build/run/script/manifest/state probe passes.
Documentation audit passes 136 files, 301 link-checked files and 19 audited
entry points; generated LLM documentation is current. These pre-repair results
are preserved separately from final volatile-repaired verification.
Both migrated executable examples build and retain exact expected stdout.
The first full fixture attempt produced all child results but its Bash parent
failed because root edited the executing harness. That interrupted run is
preserved as evidence and is not counted as a passing corpus run. The one
actual package raw-tag fixture failure is corrected to the namespaced type;
other initial failures are reviewed representation snapshots and a corrected
lambda diagnostic origin. The stabilized rerun completed all 875 fixtures: 40 expected-artifact
differences across 25 cases, with all runtime stdout/status phases matching.
The required volatile repair is separately recorded above; reviewed snapshot
updates and the repaired-image check are recorded below.

Final category measurements include new files, templates, wrappers and glue.
Relocations are reported separately: 2,460 lowering lines within production,
1,566 autodiff lines within production, and 445 recursive Match lines from
production to tests. Production net deletion therefore subtracts the 445-line
category transfer when assessing actual deletion. Generated documentation and
fixture snapshots are not authored source savings. Separate transaction,
conversion, project and full-transfer alternatives are measured independently
and never added to the integrated total.

Publication gates and push remain intentionally unattempted while Gary reviews
the research candidate. Timing, Var helper pointer-signature review, the remaining full
lowering/cache/transaction replacements, retirement patches and the explicitly
uninvestigated rows above remain open.

The volatile-repaired combined image passes 950 tests/20,785 assertions and
self-hosts with identical stage1/2 output (180 C/H files). Error floor and
shutdown probes pass. All 25 reviewed snapshot updates compile/run successfully.
The final repaired-image check passes all 875 fixtures (2,012 artifacts).
Final documentation and derived-output checks pass; git diff --check passes.

### First-wave integrated line accounting

These counts use `git diff --no-renames --numstat` plus every untracked
review file, so new templates, declarations, helpers and glue are included.
The reproducible counter and per-file JSON are in campaign-patches/.

| Category | Added | Deleted | Net added |
| --- | ---: | ---: | ---: |
| Production source/build glue | 5,037 | 6,261 | -1,224 |
| Tests and harness | 641 | 25 | +616 |
| Executable examples/manifest | 4 | 4 | 0 |
| Generated fixture expectations | 4,422 | 2,658 | +1,764 |
| Authored documentation | 484 | 45 | +439 |
| Derived documentation | 1,634 | 2,354 | -720 |
| Mixed repository total | 12,222 | 11,347 | +875 |

The production row includes the 445-line recursive Match transfer to tests.
Excluding that relocation leaves 779 actual production lines removed.
Production plus tests/harness and examples removes 608 authored source lines
across the repository. Autodiff's 1,566-line package move and lowering's
2,460-line owner move already cancel within production; neither is added to
that deletion. Generated snapshots grow because ordinary AST is spelled out
in expectations. Source deletion is not a claim that every repository category shrank.
The mixed total includes this report, documentation and generated snapshots.

The final review bundle is `.context/campaign-patches/integrated-review.patch`.
Exact category/per-file counts are `integrated-measurement-final.json`.
Failed and alternative patches remain alongside it, including previous-campaign
copies. No commit, publication gate, push, release or main update was attempted.
Current origin/dev remains df3b4382 and the original 6e4089e9 candidate is intact.
Performance approval remains open; current unrelated VM/XProtect load is saved
in debug/final-performance-host-load.log. The research retains working
prototypes without claiming the full campaign or all hypotheses complete.

## Code-quality continuation

The seven significantly-better areas were revisited with isolated workers.
Root retains five incremental patches: compatible native Array composition,
direct catchcases ownership, shared collected-script classification, common
Error handler/traversal mechanics, and one CLI eligibility error path.
Production +81/-95 removes 14 more lines; fixture source +2/-4 removes two.
There are no new relocations. These are measured follow-ons, not another
Array/Map-sized saving. Working/failed alternatives and per-area evidence are
preserved under `.context/second-wave/`; summary.md states exact scope.

The previous claim that Array.try_next was new was wrong: it already exists
on dev and in Lisp registration. Only try_get was accidentally exposed.
The corrected composition retains try_next, removes boxed try_get, and restores
the original four-argument native family, including its checked reads and raw
indexing. An initial split would have required extra native caller invocations;
that working preliminary patch was superseded. A namespace-shadowed hole
failed compilation; the corrected $family hole uses existing composition.

Canonical catchcases now survives until ordinary control-flow construction.
The catcharms rename and mirrored rewritten pattern/body records disappear.
Review corrected binding allocation order before retention. Generated C stays
unchanged in twelve focused fixtures; four transform snapshots only change
origins/formatting (two found by the root full fixture run). Adapter cache lookup/publication already has one small
owner; reviewed source-specific thunk/handle/header placement remains explicit.
No new generic cache/placement framework was retained.

Collected-script handling runs after the shared parser's visibility/linkage
prefix; the shallow loop no longer repeats that classification. This adds
seven lines, trading a duplicated control-flow owner for one explicit operation.
Error handler initialization and accumulated-record traversal share existing
operations; publication timing, canonical promotion, explicit-region copying,
watermarks and allocation-free fatal paths remain. Further mutex/Context review
found no additional substantial deletion: Pool/Scope and Buffer nested storage
have distinct lifetime work; tiny aliases would not simplify their ownership.

CLI direct request-List construction builds and preserves argv order, but
adds a reversed canonical spine. At 1000 define pairs the probe records 2001
extra cells and 32016 extra requested bytes. The corrected retained boundary
keeps existing Array builders. That alternative is preserved, not generalized
into a rejection of native forwarding metadata. No timing claim follows from
allocation counts. Complex native forwarding remains open; the metadata's
simple application and eligibility ownership stay consolidated.

Root combined verification: 950 unit tests / 20785 assertions pass; stages
1 and 2 match across 180 C/H files; package build, CLI boundaries and docs checks
pass. The full 875-fixture run found only two remaining transform-origin
snapshot differences; token comparison confirms numeric origins/whitespace
only, with unchanged C/runtime phases. After authoritative regeneration, both
focused fixture checks pass. The original failure log is preserved. Worker
checks additionally cover the restored native family and absent boxed getter.

Cumulative authored production is +5070/-6308, or 1238 fewer lines including
445 moved to tests: 793 actual production lines removed. Tests/harness are
+637/-23, including that relocation; examples are +4/-4. Production, tests and
examples together remove 624 whole-repository source lines. Typed-family
Array/Map's six production files account for 725 net lines removed. Generated
expectations and documentation are measured separately in the saved JSON;
first-wave accounting above remains historical. This batch adds no relocation.
Publication remains held; Var helper function-pointer compatibility and quiet
performance timing are still open. Unattempted original proposals retain their
prior dispositions; this continuation does not silently mark them complete.

## Lowering performance correction

The lowering merger's local identity loop revisited already-completed
subtrees at changed ancestors. A controlled replacement of only transform's
compiled implementation isolates that cost; a runtime replacement does not
remove it. Current-node rewrites now finish before descent. Synthesized
sequence items normalize explicitly, while containing blocks bind generated
defer markers to their complete suffix. This keeps the shared lowering owner
and introduces no general AST memo or return to separate passes.

Two preliminary corrections failed: one left generated syntax unlowered;
the next ran generated cleanup too early. Their actual patches, failures and
corrections remain in .context/stage3-investigation/isolation/normalizer-evidence.
Only the corrected third implementation is integrated. It adds five net
production lines (+25/-20) and reduces parse.x node visits586655->63288 with
identical C/H in the counter check.

Controlled twice-run CPU batches, using identical inputs and matching
declaration interfaces: compiler sources5.84->4.04 seconds (dev4.26);
library4.39->3.61 seconds (dev3.71). Complete four-stage paired build
30.19->24.65 seconds; Makefile lib/src parallelism remains unchanged.
This diagnoses and mitigates the slowdown; it is not a quiet calibrated
nightly performance approval or a full-build speed claim against dev.

950 tests/20785 assertions pass; 17 focused fixtures pass unchanged; root
builds through stage3 with180 C/H matching between stages1/2 and2/3.
Full875 fixtures find only numeric origins in ast-leaf-contract; C/runtime
phases pass, and authoritative snapshot regeneration passes focused checks.
After regeneration, the final rebuilt compiler passes875 fixtures/2012
artifacts. Root rebuilt the package and checked documentation. Source and test
accounting above is the pre-correction continuation: this five-line growth
leaves788 actual production lines removed (excluding445 relocated to tests),
and619 whole-repository authored source lines removed. Generated output and
documentation remain separately measured. Publication is still held.


## Readiness correction

The public Var.update/postfix C function-pointer types are restored to Var *.
Their bodies have one volatile-aware implementation each; public wrappers
forward to it and compiler-generated updates call it directly. The same
-Werror C probe passes on dev, fails on the original volatile-signature
candidate, and passes after repair. Direct, aliased and postfix writes across
caught raises pass, as do 14 Varops tests / 5340 assertions and selfhosting.
The fatal probe now reports the actual internal raising function; cause,
detail, public owner and nonreturning behavior remain. This changes the
incidental source-function label in two diagnostic expectations.

Original Map generator invocation forms and their conversion, boxing and
iterator operations are restored through thin composed templates. Both
custom-family fixture sources again equal dev byte for byte. Composing Name
holes exposed an existing forwarding projection defect; the existing Expr
projection path now also preserves Name identifier expressions. The original
consumer passes on dev, fails on the earlier candidate, and passes repaired.
Five related Name/template fixtures, 40 Map tests / 5403 assertions, and
180 selfhost C/H comparisons pass in the worker. This correction adds five
production lines and removes twelve temporary fixture migration lines.

Final gating exposed stale autodiff modules after compiler changes. The unit
build now refreshes the existing package for compiler, runtime and macro
changes, recreates a missing module, and orders fixture imports after that
refresh. Existing package fingerprints retain incremental reuse. A missing
module is recreated; an unchanged unit invocation does not retranslate the
suite. This repairs build correctness without adding a check or gate.

The first gate stopped at bootstrap stage0 comparison because the old emitter
had produced its first refresh. The next refresh reached stable output. A
later gate stopped at the stale autodiff module, then at the changed source
function labels in fatal diagnostics. Actual full logs remain in debug under
readiness-agent-pr-check*. No failed gate is reported as successful.

Two nine-pair diagnostic runs found capacity1024 timestamp-cache churn used
19.6% and15.7% more user CPU than dev. Their patch and raw samples remain in
.context/readiness-performance. A circular ring replaces that implementation:
one head owns ordering, its predecessor is least recent, and pinned entries
alone require traversal. No overflow ranking or full-capacity victim scan
remains. After the hit-path correction below, this is +24/-21 against dev,
three lines added, rather than the stamp prototype's eight lines removed. It is a small bookkeeping simplification. Eleven
cache tests /338 assertions and debug, optimized and sanitized benchmark
correctness pass in the worker.

The integrated ring's longer nine-pair run measures capacity1024 churn at
1.001x dev user CPU, versus the timestamp penalty. Mixed boxed/typed Array
and Map workloads measure1.008x,1.028x,0.981x,1.044x respectively. The same
generated C links each runtime and checks receipts; hit and eviction lanes
cover capacities32,128,1024. Samples are provisional under sustained unrelated
host load: small deltas do not establish parity or regressions, and this is
not a quiet-host performance snapshot. Final root gate and committed-candidate
measurements are recorded in .context/readiness; publication remains held.

At this revision authored production totals +5132/-6323,1191 fewer lines,
including445 moved into tests:746 actual production lines removed. Tests and
harness total +636/-23, including that move; examples +4/-4. Whole-repository
authored source removes578 lines. The six Array/Map production files remove
720 net lines. Generated bootstrap output, fixture expectations and derived
documentation are measured separately, not credited as authored deletion.
Original unattempted proposals and partial hypotheses retain their dispositions.


The next complete gate passes875 fixtures/2012 artifacts and950 tests/20785
assertions, then fails the raw/CPP symbol sweep only on merged transform.x.
New include cycles feed transform back into itself while the host preprocessor
ignores pragma once for its main file. The expanded input contains the entire
body twice, including PrintfLength. Dev has one copy; the current compiler also
passes dev source. Relocating the enum after includes still fails, and that
actual preliminary patch and logs are preserved. A source-cycle guard, defined
only under X2CCPP, preserves ordinary generated C/header declarations. Focused
raw and CPP translation now succeed and produce identical C/H; native -Werror
compilation passes. No enum is renamed and lowering remains consolidated.
Final gate results after this correction remain recorded separately.

The guarded tree then passes all638 raw/CPP comparisons,875 fixtures and950
unit tests. The gate stops only at generated API source-link offsets changed
by the guard. Authoritative doc generation refreshes those links; the final
recheck is recorded in debug/readiness-agent-pr-check-doc-final.log. Before the runtime follow-up,
separate deltas were authored docs +668/-45, derived docs +1651/-2346,
bootstrap output +26666/-27731, and fixture output +4460/-2691. Together with
then-current source categories, all measured files grew49 lines overall;
583 fewer authored source lines is not a claim of deletion across all repository text.


## Runtime performance follow-up

The committed candidate passes the complete correctness gate. Two additional
paired runs nevertheless show roughly 6% more CPU for boxed Array workloads.
Removing only their four find/count scans restores parity for push, reads,
writes and compound updates. Swapping Array objects between archives also
removes the slowdown in either direction. Matching hot instruction sequences
do not prove matching performance: function placement, register allocation
and equality dispatch remain under investigation. Actual disassembly and
samples are preserved in .context/readiness-performance/array-diagnosis.

Match hit measurements identify unnecessary ring neighbor updates when its
least-recent entry becomes most recent. Rotating the head preserves exact LRU
order without those updates. The correction passes 11 cache tests /338
assertions and a 10,000-touch independent ordering model in the worker. Root
builds it successfully. Longer nine-pair cyclic tests measure hit CPU ratios
0.949,1.038,0.996 at capacities32,128,1024, and eviction ratios
0.999,1.011,0.992. General random-hit tests measure 1.009x and1.008x at capacities128 and1024.
A hot-eight subset initially appears 12-17% slower at1024. Scratch counters
show its median bucket comparisons rise15.4% between processes because
pointer-key distributions differ; unchanged hashing and near-matched
comparison-count samples do not establish a ring regression. Counter patches
and raw observations are preserved separately. Root validation follows.
This cache representation has a modest ownership benefit but no net deletion.

All these timings remain diagnostic under unrelated sustained host load.
Neither correctness nor isolated favorable samples establish a completed
quiet-host performance checkpoint. Publication remains held.


The bounded Array follow-up tries a remaining-count pointer walk, then a
corrected pointer-range loop in the shared core template. Both preserve
comparison order, first-match stopping and ordinary Var equality. The range
initially reaches baseline timing but does not retain it on repeat; the full
workload slows roughly5% for ordinary updates and10% for compound updates.
Both actual patches and correction evidence are preserved; neither is
integrated. Temporary function alignment likewise has mixed results and is
not retained as a production flag. This rejects those implementations, not
typed-family consolidation.

The exact root runtime after the cache correction measures boxed Array
96.960ms dev versus94.308ms candidate median user CPU across nine paired
samples; compound updates measure107.409ms versus107.582ms. A newly linked
search-only probe measures find+0.7%,count+3.3%,direct equality+3.3%. Swapping
objects, changing alignment and relinking probes change these deltas even
without changing equality instructions. The earlier mixed-workload slowdown
is therefore sensitive to compiled placement and surrounding runtime code,
not an established added algorithmic cost in the template. Its precise
microarchitectural mechanism remains unproved. The candidate retains its
original shared search loop. A scratch String equality override verifies
ordered callbacks, first-match stopping, complete counting and no callbacks
for empty/null arrays. Numeric descriptor rows reject this registration API,
correcting the preliminary assumption that those callbacks were replaceable.

These observations are recorded in .context/readiness/scan-isolation and
.context/readiness/cache-hit-analysis. No production debug counters, arbitrary
alignment flags or specialized numeric equality implementation are retained.
Final correctness validation is separate from a pending quiet-machine
performance snapshot; no merge or push is authorized by favorable diagnostics.
