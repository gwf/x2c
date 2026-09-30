# x2c as its own best example

> Status: active - 2026-09-29.
> Gary authorized implementation and feature-branch pushes in this campaign.
> Integration branch: `codex/self-language-beauty`.
> Merging or pushing into `dev` or `main` requires Gary's explicit approval.
> The independent review is complete; implementation begins with the waves
> below. This plan owns the full recommendation inventory and its outcomes.

## Result and authority

Make the compiler and runtime express their own canonical Types, bindings,
AST grammar, evaluation order, and lifetimes directly. Repair the reproduced
semantic defects and remove duplicate owners and cumulative construction.
Prefer deletion, existing operations, and one small shared owner, in that
order. A lower total authored line count is desirable, not an acceptance quota.
Do not trade readability, compatibility, or runtime cost for a smaller number.

The parent chat integrates and reviews work from independent worktree sessions.
Gary authorized these additional sessions beyond the internal subagent limit
and authorized implementation after the plan is prepared. Workers deliver
local commits as integration inputs; only the parent publishes the validated
campaign branch. No worker or parent merges/pushes into protected branches or
releases anything without the later explicit approval. No attribution or
session links belong in commits, code, or PR descriptions.

A recommendation is complete when it is implemented and verified, or when a
comparable scoped investigation records why the proposed change should be
kept, revised, or escalated. One failed prototype rejects that implementation,
not the entire candidate family. Every inventory row receives evidence and a
final disposition; uncertain candidates cannot disappear from the campaign.

## Evidence and baseline

The [independent source review](source-beauty-review.md) records conclusions
formed before reading plans or git history. Baseline source tree:
`247b7fbe59198517a86a3d1f041448f0c9d30f90`; fetched `origin/main` initially
matches it. Review probes and full logs are under the parent worktree's
`.context/source-review/probes/` and `debug/source-review-*.log`; they must be
reproduced in each worker before repairing a reported defect.

Existing checks passed: 722 compiler fixtures, 925 main-suite and 20 thread
cases, 255 optional package tests, ordinary examples, 338 book samples,
documentation/site checks, and equality of stages 0/1/2 on 178 generated C/H
files. This is a baseline, not a correctness claim for the proposed changes.

The existing metrics tool records compiler 34,432/runtime 29,204 physical
lines and total `source_lines=112395`. Its categories include tests/examples
and generated prelude material; do not present that as all production code.
Keep the baseline JSON and `make stats` output in `debug/`. At completion,
report the same metric delta plus authored production/test/documentation and
generated-artifact deltas from git. No code is moved to another category just
to claim a reduction. No host installation or developer-selection change is
needed: the configured toolchain and package dependency cache already work.

## Compatibility and scope

Preserve canonical List identity/suffix sharing, binding identity, target
native Type/ABI, visibility/linkage, source/evaluation order, preprocessor and
initialization placement, rollback, allocation/error/cleanup ordering, and
owner-specific copying policies. Preserve deliberate public diagnostics,
caller obligations, package interfaces, native arithmetic promotions, cache
semantics, and editor byte/UTF-16 boundaries.

Repairing the documented SDK composition, native value loss, wrong shadowed
qualification, constructed/source order mismatch, JSON locale bug, and
manifest duplicate acceptance is authorized. Single evaluation of a Lisp
match subject is selected here as the ordinary pattern-dispatch behavior;
update its documented semantics and regression coverage. Any broader public
API/ABI change, dependency, caller burden, or unsupported native target needs
a concrete proposal and Gary's decision. No arbitrary constructed-syntax
origin check, eager Lisp collection, universal copying framework, persistent
AST/cache scheme, or house-style compiler warning is authorized by this plan.

Existing readiness targets remain intact. Add focused regression cases for
actual observable defects in existing suites/fixtures; do not add recurring
gates, mandatory heavy benchmarks, or new publication steps. The parent uses
the existing publication proof for coherent batches. Optional stress,
sanitizer, package, and platform experiments remain optional checks selected
when they answer a current question.

## Orchestration and dependencies

The following roles are bounded implementation sessions, not a second project
framework. Each starts from an observed integration commit, creates its own
`codex/beauty-*` branch, and edits only its leased authored files and relevant
regression inputs. Record actual chat/worktree/branch/base/commit/check state
in the parent's ignored `.context/source-beauty/` ledger, not in source code.
Use the configured default session model. Retain worktrees until their work
is integrated and validated; archive only after checking recoverable state.

| Wave | Session | Recommendations | Authored ownership |
| --- | --- | --- | --- |
| 1 | A: canonical compiler facts | R01-R04, R06, R32-R33 | lambda, cleanup, type numeric helpers, expressions numeric crossings, macros numeric SDK bridge, compiler native scalar lookup, compiler-sdk.xlisp |
| 1 | B: semantic sequencing | R05, R18 | parse control-flow binder, statements matching semantic steps, etc/init.xlisp match-case |
| 1 | C: runtime ownership | R12-R16, R20 | Error/private types, Logger, Match normalization, typed-array literal rows, Map growth, Func catches, Pool/Thread startup |
| 1 | D: sequence construction | R10-R11 | Args, Regex, autodiff macros |
| 1 | E: package source | R24-R26 | BLIS input traversal, libuv phase watchers, Torch generator and its generated projection |
| 1 | F: JSON numbers | R17 | private JSON numeric conversion/formatting owner; String.try_double remains its current contract |
| 2 | G: canonical frontend grammar | R07-R09, R29 | type AST grammar, compiler field-order/semantic operations, expressions/protocol Self and delegates, parse shallow generated signatures, iter/lisp/logger declarations and varops investigation, SDK argument extraction |
| 2 | H: backend and build facts | R19, R22-R23, R27-R28, R31 | cleanup/emit local statics; build/project/CLI; generate/cache templates; emission/worker receipt only where needed |
| 2 | I: compiler-owned authored facts | R21 | optional development tool over ordinary Frontend/parser/tokenizer, source declaration spans, doc consumers; coordinate overlapping compiler files with G/H |
| 3 | parent + independent review | R30, R34-R35 and all dispositions | connected style/doc cleanup, authored/generated review, integration verification, metrics and delivery |

Wave 2 starts from reviewed wave 1 integration. G owns type/parse/SDK edits
only after A/B finish. H owns cleanup after A and coordinates any cache or
compiler record change with I. I can prototype its development tool earlier,
but parser instrumentation waits for G's file lease. Package work is largely
independent, though generated include/header/publication changes still pass
through the parent. Workers may split commits along coherent operations;
commit count is not a process requirement or an artificial unit of design.

Start workers with `BUILD_JOBS=2` for focused builds to avoid simultaneous
full-host compiler jobs. A fresh worktree runs `make build-safe` into `debug/`
before using its stage0. Workers run focused verification and commit reviewed
authored changes locally; they do not run broad publication components merely
to prepare an integration input. Parent batches complete changes, reviews the
result, regenerates through the existing gate, and publishes only the passing
feature tree. No worker copies generated bootstrap C/H into another worktree.

## Recommendation inventory and execution decisions

All rows initially remain pending. Update each with final commit or concrete
keep/escalation evidence; the inventory is the completion checklist.

### Canonical facts and meta-language

- **R01 - callback return Types (A).** Replace partial return decoding in
  `lambda.x:884` with `_typed_function_parts`; retain full return modifiers,
  parameter families, variadic policy, and pointer/reference/closure handling.
  The wide unsigned callback must compile and preserve 0x100000001; check
  existing callback/capture tests and relevant generated function signatures.
- **R02 - native size results (A).** Give sizeof and related native-size
  expressions their correct target native family before Var conversion.
  The inert 4,294,967,297-byte type must box that value without allocation.
  Audit offsetof and pointer-difference consumers as candidates, reproducing
  them separately before claiming the same defect. Preserve target widths.
- **R03 - numeric meta-source (A).** Share range-preserving numeric production
  for lifted Lisp integers and `x2c.literal.int`; source and meta-source must
  agree in value and compatible native family. Cover small/wide/negative
  values, signed minima, and available unsigned boundaries. Complete
  literal.value extraction for the supported captured numeric families without
  replacing source literal spelling/reflection. Probe floating constructor
  behavior; do not silently redefine a public integer constructor. Use existing
  Type/Var conversion owners, not a second native width table. Decode numeric
  values through the runtime ledger; Var.str/repr are not canonical numeric C
  spelling for every width/sign. Keep the SDK constructor pure and available
  outside active expansion; no expansion guard is added just to share it.
- **R04 - cleanup bindings (A).** Keep exact designated bindings in preserved
  local/holder/alias maps instead of spelling. Reuse designation helpers and
  existing lambda/region identity conventions. The shadowed inner variable
  stays nonvolatile while the actually changed binding still survives cleanup.
  Cover indirect holders, deferred captures, aliases and labels separately.
- **R05 - source/constructed sequencing (B).** Bind try body then catches then
  finalizer, and match subject then arms, in their actual scopes. Share existing
  begin/finish semantic operations where it deletes coordination. Direct and
  constructed probes must agree in compile-time effects, guards and binder
  visibility. Do not rebind already bound source or add callback traversal.
- **R06 - composable SDK names (A).** decl.make and param.make accept the
  documented x2c.ident operand through the ordinary canonical name owner.
  Retain existing valid String callers and binding/name semantics. Both tagged
  declaration and parameter use compile; the declaration control still prints 42.
  No origin check or custom AST validator is introduced.
- **R07 - visible declaration grammar (G).** Convert the connected canonical
  cases of `_from_ast`, field-order and Self declaration lowering to named
  Match captures/templates. Reuse declaration_parts/parameter_ast/declaration_ast.
  Preserve modifiers, typedef/native/aggregate identity, unnamed parameters,
  field order and reconstructed Type equality. Compare representative AST,
  interface/header projections and the whole fixture corpus. Do not flatten
  initializer cursor/ordinal/rollback code merely because it is procedural.
- **R08 - receiver-relative signature owner (G).** One binding-based semantic
  operation owns Self substitution; expressions/protocols retain their distinct
  lookup policies. Cover aliases, imports, packages, delegates and protocols,
  with exact interface metadata and native signature compatibility.
- **R09 - shallow generated signatures (G).** Let ordinary generated function
  definitions contribute signatures through the existing declaration collector
  without binding bodies or evaluating arbitrary Lisp earlier. Preserve source
  order, visibility/linkage, scopes and Self. Reuse the existing nonstatic
  fn_defs and static visibility-marker rules. Keep bodies deferred and local
  eligibility unchanged; do not delete the shallow early-return and then bind
  full generated functions. Probe private header/.xi exclusion, counter stability
  and body effects exactly once. Only then remove the eight imported converter
  declarations in iter/lisp/logger
  and repair the adapters guide. The fourteen local varops update prototypes
  have a separate selective-eligibility boundary: keep them and correct their
  phase comment, or prove a small ordinary imported generator extraction
  before deleting them. Do not broaden local Unit eligibility implicitly. Prove protocol
  conversion before full parse, forward references, imports and source capture;
  if selective collection cannot preserve these, record the exact constraint
  and a bounded alternative rather than deleting declarations blindly.
- **R29 - smaller AST projections (G).** Replace procedural delegate-row shape
  interpretation and `_x2c.arg` nested selectors with named grammar captures
  or existing parameter operations. Keep delegate lookup/ABI differences and
  empty/void/unnamed parameter behavior. Retain an existing direct operation
  when a new abstraction would hide more than it removes.
- **R32 - native typedef scalar lookup (A).** Probe whether full String names
  collide after compact Symbol conversion in `_builtin_typedef_scalar`.
  Preserve native typedef identity with full-name lookup if reproduced.
  Do not claim a tag-collision defect in `_from_ast`: that earlier hypothesis
  was withdrawn after verifying String/Symbol distinction.
- **R33 - direct-function recognition (A).** Compare duplicated recognizers in
  lambda.x:256/464. Share the common structural predicate while retaining their
  deliberate cast-stripping difference; verify capture/adaptation behavior.
  Keep separate code with evidence if a mode-driven helper is less direct.

### Runtime construction and lifetime

- **R10 - forward runtime builders (D).** Accumulate repeated Args and Regex
  capture names privately and freeze once. Preserve occurrence order, defaults,
  named capture indexes, failed parse cleanup and published List identity.
  Reproduce the 500,500 versus 1,000 cell comparison at 1,000 elements; verify
  actual changed modules with their suites and bounded scaling measurements.
  The local result Map may hold temporary builder slots during parsing, then
  publishes Lists at the existing boundary. Preserve the accepted duplicate
  repeated-row-name reset/share behavior according to argv order; independent
  per-row publication in spec order would change it. No Array temporary
  escapes through a public Map or callback.
- **R11 - autodiff fragments (D).** Use shipped `(apply append lists)` for
  ad._concat. Accumulate forward/exit fragments then concatenate once; preserve
  reverse/pruned-exit sequencing. Run autodiff derivatives/examples including
  branching, loops, early returns and generated placement; compare canonical
  resulting syntax and measured cumulative construction, not just output size.
- **R12 - flat List spines (C).** Error copy/snapshot, Logger retention and
  Match normalization iterate cdr spines and recurse only into heads, following
  Context/prepared-Match owners. Preserve Error leaf rejection, Logger borrowing,
  Context moving, explicit pools/wide Scope and original tail identity where
  it applies. Include Match literal-list admission if its cdr recursion would
  move the same stack failure downstream; preserve untouched explicit-pool
  suffixes instead of reinterning them in the current chain. The 200,000-value Error probe reaches catch without native stack
  exhaustion; cover nested values, snapshots, release and matching behavior.
  Keep the optional recursive Match oracle as an independent oracle.
- **R13 - one Error canonical pool (C).** ErrorRegion owns one Pool for both
  Strings and Lists, as explicit snapshots already support. Remove duplicate
  allocation/retention/release fields without changing wide-value Scope or
  borrowed-owner rules. Check record/view/snapshot lifetime, watermark order,
  cancellation and release; use allocation/owner evidence to confirm deletion.
- **R14 - remove 49 typed-array rows (C).** Delete the redundant literal Self
  signatures and stale phase comment. Prove all seven families/methods,
  derived aliases and imported interfaces, not only the isolated fresh family.
  Compare .xi/generated headers and collection/iterator suites. This is
  independent of R09; private definition-only converter prototypes stay until
  signature collection changes are proved.
- **R15 - Block transfer owner (C).** Replace Map's paired manual backing/handle
  moves with Block.move_to. Keep replacement arrays staged and commit order
  unchanged. Verify Map growth, scope export/move, stable handles and failures;
  existing Block/Array transfer paths establish the producer contract.
- **R16 - Func cause mapping (C).** Consolidate five identical catches only
  using capture AND the admitted cause alternatives. Allowed causes retain
  detail and translation; an excluded cause propagates. Do not use a binder as
  an OR alternative that catches everything. Keep the current catches if the
  tested idiom adds complexity; document that measured/source-based outcome.
- **R17 - JSON numeric locale (F).** Give JSON parsing and formatting one private
  C-locale policy. Preserve decimal grammar, exact roundtrips, range failures,
  signed zero and supported native platforms. Never set the process locale or
  change String.try_double's general contract. The de_DE child parses 1.5 and
  emits valid dot-decimal JSON; test normal locale, exponents, boundaries and
  threaded independence. Use the supported POSIX locale API privately: cache
  the C-numeric locale
  through one startup owner, enter/restore the thread locale only around C
  conversion/formatting, and restore before any allocating/raising x2c call.
  Probe macOS/Linux/MSYS and the configured optional Cosmopolitan interface;
  avoid exposing GNU feature macros or locale objects in public headers.
- **R18 - match-case subject (B).** Bind its subject once outside the generated
  clause chain. Preserve pattern order, captured binder scope and else behavior.
  The side-effecting first-miss probe increments once; check macro hygiene,
  nested dispatch and existing SDK/autodiff/Lisp behavior.
- **R20 - Pool startup transition (C).** Reproduce/prove the later Thread.start
  write/read pattern; make the first transition occur once before worker
  creation, preferably inside the existing startup-once owner. Preserve the
  pre-worker allocator fast path and failure cleanup. Inspect emitted native
  accesses and exercise an existing worker while starting another; TSan is a
  focused optional probe if available, not an install or new recurring gate.

### Native packages and compiler tooling

- **R24 - BLIS sequential inputs (E).** Traverse admitted Lists sequentially
  for validation/filling rather than repeated positional lookup. Arrays retain
  direct indexing where appropriate. Keep all input validation before native
  allocation where currently promised, shape/numeric diagnostics and cleanup.
  Test List and Array matrices/vectors, empty/ragged inputs and package results;
  measure representative List scaling before/after.
- **R25 - libuv watcher family (E).** Prototype a bounded Unit family for
  idle/prepare/check only. Preserve distinct native types, event timing, handle
  release, stop/close/errors and callback unwind. Inspect generated signatures
  and run relevant libuv examples/tests. Do not generalize unrelated handle
  lifetimes. If family expansion needs metadata support, sequence after R09 or
  retain minimal necessary declarations with evidence.
- **R26 - Torch result generation (E).** Change gen-ops.py, not generated
  operators by hand. Fixed tuples can publish one literal; variable-length
  results build privately then freeze. Preserve native-handle adoption and
  cleanup on partial failures. Regenerate through the package's documented
  target; compare public signatures/operator inventory and run package tests
  and training/checkpoint examples using the existing cache.
- **R21 - compiler-owned authored facts (I).** Implement a bounded optional
  development extractor over normal Frontend/parser/tokenizer boundaries.
  Return authored declaration identity/extent/doc adjacency and byte spans;
  use canonical .xi types where already authoritative. Migrate documentation
  consumers to those facts and delete the corresponding second-parser paths.
  Keep build-free metrics/lexical audits independent of the compiler, and keep
  editor name ranges/UTF-16 conversion unchanged. A single token/span reader
  may serve build-free tools, but must not become another semantic parser.
  Compare declaration/doc output across the complete authored inventory and
  generated docs; cover legal Symbol delimiters, expression bodies, macros,
  decorators, aliases, Unicode comments/byte positions and include visibility.
  No new public lint subcommand, AST-in-.xi payload, eager Lisp or persistent
  cache is part of this change. Coordinate rather than silently implement the
  broader needs-author-scoping lint plan. A development tool can link the
  existing compiler library; do not require it for bootstrap recovery tooling.

### Backend/build owners and final source review

- **R19 - manifest section presence (H).** Distinguish allocated/present Map
  from nonempty contents using the existing presence owner. Duplicate empty
  dependencies must reject with the established section diagnostic; ordinary
  empty/filled manifests retain behavior. Cover manifest ordering, file/base
  paths and dependency receipts in existing project/CLI probes.
- **R22 - localstatic classification once (H).** Carry per-binding native vs
  runtime initialization decisions from cleanup into emission in the smallest
  canonical form. Keep emission-owned typeof/extent/alignment/byte copying and
  runtime guards, concurrency, retry, thread-local storage and switch-entry
  diagnostics. Prove arrays, scalars, errors/retry, recursion, jump boundaries
  and generated output. A normalized form earns its place only by removing
  repeated classification; no blanket relocation of C spelling into the AST.
- **R23 - generated include placement (H).** Prototype final emission include
  facts consumed by Build, including cached worker outputs. First reuse the
  existing depfile as a marked comment record with its word escaping, rather
  than adding a sidecar, .xi payload or persistent graph. Delete generated
  C/H string reparsing only when finalized/constructed includes, nested paths,
  precedence and cold/warm caches agree. Source collection edges and declaration
  filenames cannot establish final native includes. Keep native preprocessing
  fingerprints. Compare implementation size and metadata lifetime; if no
  simpler compatible owner emerges, document the exact evidence and retain
  the current scan rather than add a second source graph.
- **R27 - generated guard/call templates (H).** Share only repeated guard/call/
  patch construction between generate.x and cache.x. Preserve protocol bootstrap,
  cache reachability, early/mid/late initialization and shutdown order. Compare
  relevant emitted AST/C/H and cache tests. Avoid modes for distinct lifecycle
  policy; templates should expose the shape they build.
- **R28 - command text construction (H).** Replace cumulative immutable String
  accumulation in Build/Project with existing Buffer or joins, preserving
  exact text, quoting, error paths and ordering. Run command/manifest receipt
  probes and before/after output comparisons. Do not build a formatting DSL.
- **R31 - empty long options (H).** Probe explicit empty String options against
  omission, CLI docs and each consumer. Preserve deliberately accepted values;
  fix only demonstrated accidental defaulting/contract contradictions with
  existing argument validation. No blanket new rejection policy or negative
  fixture for a merely earlier diagnostic. Record any remaining public choice.
- **R30 - scoped style/comments (parent/all).** Reflow awkward wrapping and
  replace narrating comments in touched authored code after structural work.
  Use current style and idioms; leave unrelated files alone. Comment changes
  explain invariants or reasons, not the syntax visible beside them.
- **R34 - Diff construction (keep).** Its cons/reverse builder is already brief
  and linear. Preserve it; record this qualification of the initial builder
  inventory rather than claim every List builder is quadratic.
- **R35 - healthy complexity (preserve).** Preserve initializer cursor/ordinal/
  dimension/rollback semantics, native ABI crossings, canonical pool promotion,
  machine producer trust, Lisp tail-frame reuse and native-vs-boxed arithmetic
  policies. The completed source review explicitly checks these retained facts.

## Integration, verification and delivery

For each workstream, reproduce relevant baseline behavior, inspect its working
example/current tests, implement its connected authoritative source changes,
run decisive focused checks, then review/fix the authored diff. Workers report
base and commit, paths, behavior, checks/logs, net authored change and remaining
uncertainties. Parent verifies reported findings against its integrated source;
passing worker checks are not substituted for integrated-tree evidence.

Parent cherry-picks or integrates only into the campaign branch, resolving
semantic overlap against the canonical owner rather than textual precedence.
After coherent waves, fetch and integrate current origin/main into this feature
branch, inspect authored/generated deltas and run git diff --check. Use
`tools/gate-state.py ensure agent-pr-check` for the final code tree; it owns
bootstrap refresh, safe rebuild and stage proof. Use the docs-only command for
plan-only publication. Review every resulting artifact. Rerun ensure after an
edit, regeneration or integration changes the tree; an unchanged commit/push
needs no repeated proof. A required failure stops publication, preserves the
full log and triggers focused diagnosis without a host/toolchain repair.

Package gates and book/site checks are selected for affected areas and final
coverage; do not repeat broad gates per microcommit. Compiler transitions that
the checked-in bootstrap cannot consume require explicit intermediate proof
before ordinary final publication. Generated tests/interfaces/docs are updated
only through documented targets, and expectation changes need a source cause.

Use the explicit authorized destination:

```sh
git push origin HEAD:refs/heads/codex/self-language-beauty
```

Only a validated passing feature tree is pushed. Prepare a reviewable diff and
an ordinary GitHub review artifact if useful; keep it unmerged. Completion
requires every inventory row's disposition, source review, final gate evidence,
metrics, actual remaining coverage gaps and verified feature remote state.
Gary approves the final head and merge destination before any merge to dev/main.

## Plan review

- **Established facts:** canonical AST producers, binding identities, complete
  Type operations, valid allocation/Error transfer, Block transfer and selective
  declaration collection establish their own guarantees. Consumers retain
  those facts rather than reconstruct spelling, native widths, backing layout
  or syntax provenance. Native ABI, null/absence and JSON grammar boundaries
  keep their required checks.
- **Deletion and reuse:** reuse function Type parts, designation, begin/finish
  binding, declaration reconstruction, Array/list publication, variadic Lisp
  append, iterative Context/Match walks and Block.move_to. Delete partial
  decoders, cumulative prefixes, redundant pools/prototypes and corresponding
  doc parser paths. Any new numeric/span/static/include representation must
  replace an existing owner and demonstrate a simpler compatible lifetime;
  otherwise revise it before integration.
- **Idiomatic source:** Match and literal templates display canonical grammar;
  ordinary operations retain binding, typing, scope and lifecycle. Each private
  builder stays local to its real construction lifetime. Native arrays/locking/
  storage and separate copy policies remain where their identity requires them.
  No generic framework, callbacks-to-share-traversal, public style product or
  source-size quota earns a place merely because a test can exercise it.
- **Validators, diagnostics and fixtures:** regressions protect reproduced
  wrong values/types/order/bindings, compiler abort, stack exhaustion, invalid
  JSON and deliberate duplicate-table rejection. Existing admissibility,
  native crossing and public diagnostics remain. No new origin validator,
  redundant allocation guard, diagnostic-only recursive checker, recurring gate
  or failure fixture justified solely by more specific rejection is proposed.
  CLI/numeric extraction/native lookup candidates require actual contract
  evidence before adding rejection. Large stress and performance checks stay
  optional. The last implementation step is the authored/generated source
  review and repair before the existing publication proof.
