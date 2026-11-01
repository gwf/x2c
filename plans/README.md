# plans/

All durable planning lives here. Build tooling and runtime-loaded bootstrap
data stay in `etc/`; ephemeral per-workspace state goes in `.context/`.

- `plans/` - active plans and reference inputs. Each file opens with a
  `> Status:` blockquote, usually several lines: the state, then a note
  saying where the work actually stands. The states in use are `active`,
  `blocked`, `reference`, and `needs author scoping`.
- `plans/reference/` - dated evidence and unselected research inputs.
- `plans/archive/` - finished plans. The same blockquote, recording the
  outcome, its date, and the commit or PR that closed the plan. Write
  `done`, `rejected`, `obsolete`, or `retired`. Older entries also say
  `complete`, `completed`, `archived`, `superseded`, and `corrected`; each
  of those means `done` or `obsolete`. Never delete a plan; archive it with
  its outcome. Archived workflow restrictions record the authorization that
  applied at the time; current work follows the root `AGENTS.md`.

Keep a plan concise and decision-complete: the requested behavior, important
choices, implementation, relevant validation, and delivery should be clear to
another engineer. Use phases only when the work needs separately delivered
changes. Record measurements when they decide the design or verify its result,
rather than requiring a count for every task. Update status when work lands.

A planning-only request ends with the plan. An implementation request allows
routine missing details and the design review to be completed during the work.
Ask about unresolved consequential choices, such as public semantics or
compatibility beyond the request, rather than stopping for missing paperwork.
Delivery follows the root `AGENTS.md`; a plan need not imply a PR or another
session.

An archived rejection records the exact implementation, compiler capability,
and evidence measured at that time. It does not create a permanent rule against
the candidate family. New syntax, projections, compilation behavior, source
structure, or measurements may justify a new prototype. Treat old phrases such
as `do not reopen` or `no other candidate` as historical unless current
`AGENTS.md`, agent guidance, or an active plan restates the exact restriction.

## Current work and backlog

Reviewed 2026-10-31 against `dev` `2b7a2b422`. Completed deliveries are
archived below. Remaining implementation questions and conditional candidates
have explicit owners. Historical measurements remain evidence for their named
revisions; this closeout does not commission deferred work or main promotion.

### Active work

| Owning plan | Remaining scope | Next action |
| --- | --- | --- |
| [November 1 repository review](repository-review-remediation-2026-11-01.md) | Package inputs and ordering, literal/printf values, collection boundaries, test summaries, stale consumers, verification guidance, and historical benchmark cleanup. | Seven coherent changes are planned; String rejection, compact calibration retention, and consumer driver invocation are settled. Implementation has not started. |
| [Review follow-ups](review-followups-2026-10-31.md) | Script LSP offsets, native-module probe, lint tiers, attribute macros, Linux dependency identities, CPP overflow, example instructions, documentation gate scope, and local definitions under Macro-target decorators. | Start each selected repair with its named reproduction; do not reopen completed campaigns. |
| [Language-reference writing](review-remediation-2026-10-11.md) | Remaining rewrite explanation and runtime Lisp truthiness/host-limit coverage. | Preserve delivered AST catalog and binding explanations; fill exact missing coverage. |
| [Structured lint findings](x2c-lint-and-format.md) | Approved optional List output and compiler consumption. | Implement that interface when selected; preserve experimental distribution. |
| [Detached Channel ownership](detached-channel-ownership.md) | Historical benchmark and delivery/hold evidence closeout. | Recover the named records; implementation already landed. |

### Research and reference

These records do not commission implementation. Use their stated trigger
before selecting a candidate.

| Record | Use |
| --- | --- |
| [Deferred language and library candidates](reference/deferred-candidates-2026-10-31.md) | Conditional JSON/assertion sharing, Array rest, meta Map boundary, quotation/TagId adoption, and browser phase 3. |
| [Deferred async performance](reference/async-performance-followup-2026-10-31.md) | Accepted Channel/memory costs and evidence limits; normal benchmarks remain deferred until requested. |
| [Async execution-stack evidence](reference/async-validation-2026-10-31.md) | The eleven `reference/async-*.md` records: prototype, spike, validation, native targets, numeric and sanitizer fixes, memory attribution, review, and integration for the work published at `255de641f`. |
| [Earlier review questions](reference/review-followups-2026-10-24.md) | Dated component, typed List, duplication, SDK/native-type questions. |
| [Compiler ownership](compiler-ownership-investigation.md) | Refresh one concrete ownership candidate before selection. |
| [Compiler ownership evidence](reference/compiler-ownership-evidence.md) | Static inventory at `548b381f`, not a current census. |
| [Lifetime proof](lifetime-proof-followup.md) | Dormant extension; first name a current blocked program. |
| [Prepared formats](prepared-format.md) | Dormant feasibility work; first establish a useful repeated-format caller. |
| [Overengineering ledger](overengineering-candidates.md) | No live candidates selected. |
| [Harness evidence](reference/harness-evidence-2026-10-05.md) | Historical external incidents; repository repairs landed. |
| [Remediation evidence](reference/review-remediation-evidence-2026-10-11.md) | Dated repair and reproduction evidence. |
| [Language ledger](reference/review-remediation-language-ledger-2026-10-11.md) | Historical study coverage, not an active task list. |
| [Benchmark website integration](../site/BENCHMARKS.md) | Future page requirements and saved-data paths; no deployment selected. |

Future releases use [releasing](../agents/releasing.md) and
[deployment operations](../etc/release/README.md). No production promotion
is selected here.

### Decisions and completed records

This list is selective. Every finished plan lives in `archive/` with its own
status blockquote; only the records most often consulted are listed here.

- [Regex-redux and source size](archive/plso-regex-and-source-size.md): phase
  profiling supports scratch-buffer replacements; pidigits wrappers are removed
  with flat timing. Independent counts and refreshed charts are validated.

- [October 31 margin repairs](archive/review-repairs-2026-11-01.md): the
  post-review repair plan; batches A-E repaired three compiler defects,
  release notes, the third-party notice, and Map, Scope, task, guide, and
  record margins, with publication evidence per batch.

- [Independent Pool and Channel locks](archive/independent-pool-and-channel-locks.md),
  its [revised design](archive/independent-locks-revised-design.md), and the
  [profiled corrections](archive/independent-locks-profiled-corrections.md):
  the shipped runtime candidate `a596f6cb5` with the accepted costs.

- [Quotation construction](archive/quotation-construction.md): ordinary
  quotation construction and its adoption, accepted 2026-10-28.

- [Language server](archive/language-server.md): the resident language
  server and the verified 0.4.0 client, completed through PR #615.

- [Deferred method template name](archive/compiler-deferred-method-name.md):
  a deferred method template keeps its name, published through PR #614.

- [Name-first expression aliases](archive/alias-name-first.md): both alias
  spellings, 43 conversions, and 19 compact raises in `2816c20e1`.

- [Public-first function reading order](archive/function-reading-order.md)
  and the [optional order lint](archive/function-order-lint.md): the skill,
  the corpus campaign, and the lint candidate; further ordering is deferred.

- [Serve reusable project analysis](archive/graph-serve.md) and
  [reusable project analysis](archive/reusable-project-analysis.md):
  persistent snapshots, queries, structural matching, and the served form.

- [Pattern conditions](archive/match-condition.md): implemented 2026-10-26 in
  `94942111d`.

- [auto declarations](archive/auto-cleanup.md): `auto` declarations and
  complete initializers, implemented 2026-10-23.

- [Channels, Thread batches, and scope ownership](archive/channels-and-scope-ownership.md):
  integrated 2026-10-22; shared-scope payloads are superseded by detached
  Channel ownership.

- [Tuned PLSO kernels](archive/plso-kernels.md): chunk reads, batched sequence
  output, full threshold scanning and contiguous N-body records retain measured
  gains. Paired comparisons and the refreshed chart are validated.

- [PLSO tuned parity](archive/plso-tuned-parity.md): six tuned programs receive
  ordinary scheduling/buffering improvements; a full x2c rerun, matched source
  probes, revised tables and figures are archived with publication evidence.

- [Split grouped Map storage](archive/grouped-map-split-storage.md): large Var
  Map and Pool hash caches use Block-owned storage; peak RSS recovery and
  retained timing costs are recorded with publication evidence.

- [Robin Hood retirement](archive/retire-robin-hood-map.md): Var Map, typed Maps
  and ordinary PoolTable share grouped storage; paired performance and memory
  costs are recorded with the completed publication proof.

- [Grouped typed Map adoption](archive/grouped-typed-map-adoption.md): all five
  typed families use grouped storage at `9ef736b22`; the full benchmark report
  records gains, shared-baseline ratios and remaining coverage limits.

Archived 2026-10-31 after checking delivery and giving residual work explicit owners:

- [Recent-wave repairs](archive/recent-wave-repairs-2026-10-31.md): all six
  confirmed gaps repaired and validated; the follow-up plan owns the remainder.

- [Execution stacks](archive/async-execution-stacks.md): Task.run and Scope
  migration published as `255de641f`; performance follow-up remains deferred.
- [Async research spike](archive/async-channel-runtime-spike.md): completed
  experiment, superseded by the shipped execution-stack design.
- [Derive and test](archive/derive-and-test.md): delivery through PRs #602,
  #619, and #626; command promotion is complete.
- [Map rest parameters](archive/map-and-array-rest-parameters.md): delivered
  through `cd209b178` and `6ead2cdde`; Array rest and meta Map remain deferred.
- [Quotation closeout](archive/quotation-adoption-closeout-2026-10-31.md):
  selected typed alignment delivered as `e8be27b73`; adoption remains optional.
- [Browser playground](archive/browser-playground.md): selected phases 1-2
  delivered in PR #596; phase 3 remains unscoped.
- [Networking and flagship service](archive/networking-and-flagship-service.md):
  networking delivered in PR #598; the Notes rewrite superseded the old app design.


- [Macro-target decorators](archive/macro-target-decorators.md): implemented
  on 2026-10-31 in `f701f2703` and `c84a2828`. `expand` preserves the generator's
  result kind; returned decorators consume the following target. Publication
  validation and the compiler performance checkpoint passed.

- [Contextual x2c keywords](archive/contextual-x2c-keywords.md): implemented
  from `c5ed5ae99` through `234eec5b3` on 2026-10-30. Nine additions are
  contextual; defer and C keywords remain reserved. Full publication checks
  passed; percent/angle forms retain documented lexical priority.

Archived 2026-10-30 after checking delivery on `dev`:

- [October 30 review repairs](archive/review-remediation-2026-10-30.md):
  all six batches delivered in `fe6b9d4d7` and `8b3499587`; the review
  record and the follow-ups found are in the plan.
- [CPP as an optional C compatibility bridge](archive/cpp-compatibility-boundary.md):
  done; ordinary builds skip C macro expansion and `--cpp` enables it.
  Published in PR #641 (`517b822e5`, `3da9a42ea`) on 2026-10-30.
- [An x2c-owned C preprocessor](archive/c-preprocessor.md): obsolete. Its
  engine landed in PR #625; the boundary plan reversed its always-on premise.
  Its literal-exclusion choice was never implemented as a rule.
- [Runtime lock mitigation](archive/runtime-lock-mitigation.md): done;
  unnecessary runtime locks removed in PR #631 (`21d749b8d`) on 2026-10-29.
- [Shared-root canonical index](archive/shared-root-index.md): done; String
  and List lookups read the root index without locking. Published in
  PR #628 (`a8c3bd36f`) on 2026-10-29.
- [Notes rewrite](archive/notes-rewrite.md): done; the SQLite notes server
  was published in PR #608 (`1f4115f28`) on 2026-10-28.
- [Allocation accounting and Notes database ownership](archive/notes-accounting-and-database-thread.md):
  done; opt-in Scope accounting and the database-thread comparison were
  published in PR #611 (`6a190fa5f`) on 2026-10-28.
- [Located failures](archive/located-failures.md): done; located runtime
  conversions, mapped native diagnostics, real macro causes, expansion
  notes, the void-return check, and `--dump-expansions` were published in
  PRs #603, #604, #605, and #607 on 2026-10-28.
- [Compile startup floor](archive/compile-startup-floor.md): done; `env`
  validates the prelude interfaces it reports and `run` reuses the script
  cache. Published in PR #601 (`b8173e817`) on 2026-10-28; the replay
  retention change was declined.

- [REPL library playground](archive/repl-library-playground.md): implemented in
  `cdad3ab09` on 2026-10-29. Native sessions, discovery, source/object inspection,
  and restart behavior pass source/archive and host SQLite workflows.

- [Included static meta helper report](archive/compiler-included-static-meta.md):
  rejected as a compiler defect on 2026-10-28. Supported provider-owned calls
  pass; cross-unit static access is outside the existing visibility contract.

Completed work archived on 2026-10-27:

- [Review simplification candidates](archive/simplify-review-candidates-2026-10-27.md):
  three duplicate owners removed in `76cca9ad2`; three candidates rejected
  with evidence.
- [Match pattern tests](archive/match-pattern-tests.md): delivered in
  `5fd0a079e`; every Match operator is tested in place.
- [List rest parameters](archive/list-rest-parameters.md): delivered in
  `075623030`; its `.... name` spelling became `List @name`.

Completed work archived on 2026-10-26:

- [October 26 review repairs](archive/review-remediation-2026-10-26.md):
  R1-R12 and Q1 implemented and validated on 2026-10-26 through
  `12705c82e`.
- [Compiler Lisp independence](archive/compiler-lisp-independence.md):
  the cleanup batch landed as PR #294 (`71088fa33`); the native-compiler
  plan superseded its remaining dependencies and easy-wins limit.
- [Native compiler with runtime Lisp](archive/native-compiler-runtime-lisp.md): the
  compiler neither links nor evaluates Lisp; published in `ff3aba2aa` with
  cleanup `735e72f73`.
- [Collection reading and parenthesized unquote](archive/collection-reading-and-unquote.md):
  `$(...)` and `@(...)` replace braced insertion and splicing, `$(a, b)` builds
  a List, and `${key: value}` builds a Map; published in `b9eed26d1`.

Archived 2026-10-24 after checking source and delivery history:

- [Component foundation](archive/language-components-foundation.md): selected
  extractions delivered. Free names resolve at expansion sites except explicit
  `using` declarations, as corrected in `bcb22ae7a`.
- [October 12 review](archive/repository-review-2026-10-12.md): repair batches
  delivered; later String cast, String switch, naming, documentation, and module
  work supersede the old backlog. Remaining questions have the reference owner above.
- [c2x2c continuation](archive/c2x2c-continuation.md): delivery through
  `e2a78078e`; later explicit result ownership and Channel APIs supersede its
  concurrency description.
- [Compiler kernel](archive/compiler-kernel-minimal.md): superseded architectural
  research; old projections are not a current extraction commitment.
- [SDK and system macros](archive/macro-sdk-and-system-macros.md): delivered
  umbrella; located failure/error reporting exists. Warning and enum ideas
  remain unselected.
- [Meta follow-ups](archive/meta-followups.md): completed or declined tracks;
  native-type limitations remain dated research.
- [Temporary assignments and aliases](archive/with-and-alias.md):
  `with` assignment lists and both `alias` forms replaced `$let` and the old
  `with` alias; implemented from `ab9645f0c`.
- [Ending an alias](archive/unalias.md): `unalias name;` and source-ordered
  file-scope alias conflicts, implemented after PR 286.
- [Public release workflow](archive/public-release-workflow.md): workflow
  implementation delivered, including staging evidence at `a3084897c`.
  Closure does not claim a production release or current staging health.
- Historical [lint implementation](archive/x2c-lint-and-format-implementation.md),
  [remediation](archive/review-remediation-2026-10-11.md), and
  [quotation audit](archive/quotation-adoption-audit-2026-10-03.md): delivered
  work and earlier decisions retained; current owners above hold remaining work.

Archived 2026-10-21:

- [Build CLI defaults](archive/build-cli-defaults.md): delivered at
  `27812dffe` after integrating the upstream thread repair. Normal publication
  validation and the performance checkpoint passed.

Archived 2026-10-16 after wave closeout:

- [Module storage class](archive/module-storage-class.md): delivered in
  #196 and #197; module adoption and layout landed through #273.
- [External build workflows](archive/external-build-workflows.md): delivered
  in #237; retained submission evidence is historical.


Archived 2026-10-09 to 2026-10-11:

- [Module blocks](archive/module-blocks.md): done; delivered 2026-10-11,
  recorded by `0ff8816e`.
- [Compiler kernel hypotheses](archive/compiler-kernel-hypotheses.md),
  [component authoring study](archive/language-components-authoring.md), and
  [component experiments](archive/language-components-experiments.md):
  retired; historical records superseded by the
  [foundation plan](archive/language-components-foundation.md) and the
  [kernel catalog](archive/compiler-kernel-minimal.md).

Archived 2026-10-15:

- [String switch](archive/string-switch.md): done; delivered to dev on
  2026-10-15.
- [C on-ramp](archive/x2c-c-on-ramp.md): retired 2026-10-15. Parser and
  corpus work was delivered; the landing-page examples were reverted as
  `85d787e79` and are not planned.

Archived 2026-10-12 after checking delivery on dev:

- [Source consolidation research](archive/source-consolidation-research.md):
  selected changes delivered through `0f667604`; umbrella retired. Original
  unattempted hypotheses remain research, not a broad refactor commitment.
- [Self-expression](archive/x2c-self-expression.md): selected waves delivered
  through `9483437e` and `80bde80f`; campaign done. Useful quotation work moved
  to its owning plan; unsupported pitches dropped.
- [Meta continuation](archive/meta-continuation.md): selected operator ledger
  delivered through `b5c2dde7`; umbrella retired. Unselected experiments deferred.
- [Harness and messaging](archive/harness-simplification-and-messaging.md):
  selected repository repairs and pilot delivered through `3459d664`; campaign
  done. External incident evidence is retained without claiming external repairs.
- [Scripting ports](archive/x2c-scripting-ports.md): selected tool and documentation
  ports delivered, including later generator work through `4c114ab2`; umbrella
  retired. Compiler-backed tooling remains in the lint plan.

- [Macro sequence splicing](archive/macro-at-splicing.md): delivered through
  `f5d544eca`, `0895fe073`, and `9fd19789d`.
- [Match component](archive/match-component.md): delivered through
  `7febe4376` and `abcb8a87a`.
- [Protocols component](archive/protocols-component.md): delivered through
  `13e0b5719`, with subsequent conformance and discovery fixes.
- [Idiom synthesis](archive/idiom-synthesis-2026-10-04.md): delivered through
  `59654330a` and `27cc9a782`, with its four completed research records:
  [AST](archive/idiom-synthesis-ast-2026-10-04.md),
  [boundaries](archive/idiom-synthesis-boundaries-2026-10-04.md),
  [generators](archive/idiom-synthesis-generators-2026-10-04.md), and
  [ledgers](archive/idiom-synthesis-ledgers-2026-10-04.md).
- [October 2 fix list](archive/post-integration-fix-list-2026-10-02.md):
  delivered through `a6d155dc0`, `6ab6c1a6f`, `6e1dd3e9`,
  `715267d97`, and `63d90c26`.
- [Code standard campaign](archive/x2c-code-standard.md): approved decisions
  and selected cleanup delivered through `2a508c233`.
- [Metalanguage campaign](archive/x2c-metalanguage.md): delivery recorded at
  `df41119d`, with subsequent ordinary-source adoption at `a5cd78da`.
- [Protocol-call catalog](archive/var-protocol-call-catalog.md) and its
  [CSV](archive/var-protocol-call-catalog.csv): delivered through `649371ab3`
  and `2b1e52516`.

- [Unit initialization, entry setup, and assembly](archive/unit-initialization-and-assembly.md):
  done 2026-10-07 at `0916ff92`. One pending owner with named destinations,
  one run-once initializer builder and entry decision, single-scan source
  assembly, and shared function-entry setup; generated C is byte-identical.
- [Ordinary source modules and automatic interfaces](archive/automatic-interfaces.md):
  done 2026-10-06 at 6938c195. Ordinary includes, static storage, and public
  type dependency selection replace visibility pragmas and macro packs.
  The full required gate passed; Gary requested local retention.
- [Macro application cost](archive/macro-application-cost.md): done
  2026-10-04; phases 1 and 2 and the undo log in PR #129, phase 3 in
  PR #130, then PRs #132 and #135. Its open defer options stay under
  "Outside this plan".
- [Compiler error catalogue](archive/compiler-error-catalogue.md): done;
  catalogue and callers landed through `c08f1d84` and `bef9923d`, with
  once-only table initialization through `fcfaff40` and `2c8ddfb3`.
  The archived October 2 fix list records its delivered named-macro replacement.
- [Value declarations and reference style](archive/value-reference-style.md):
  done; private contexts landed in PR #76, and public contexts through
  `cbecd92e` and `a373970c`. F14 and F29 track the runtime follow-ups.
- [Batched dev integration](archive/batched-dev-integration.md): done
  2026-10-01 at `0e2c03a93195`; all three delivery modes are live, the shared
  tools work in both native worktree types, and PRs #74, #75, and #76 landed
  with one successful full gate. Explicit review stops remain held.
- [Source organization](archive/x2c-source-organization.md): done
  2026-09-30; one subject per file, one owner per fact, reading order, and
  record ownership across `src/` and `lib/`, with 14 new units and every
  section under 400 lines.
- [Beautification](archive/x2c-beautification.md): done; Waves 0-5
  delivered through 0bccd679. Its deferred file-level work continues in
  [source organization](archive/x2c-source-organization.md).
- [Next compiler/library beautification](archive/compiler-library-beautification-next.md)
  and its [coverage record](archive/compiler-library-review-coverage.md):
  done 2026-09-30 as PR #72.
- [Native meta execution](archive/native-meta-execution.md) and the
  [meta-integration mitigation](archive/meta-integration-mitigation.md):
  done; present on dev.
- [Macro capture-role consolidation](archive/macro-capture-role-consolidation.md):
  done at 0e2f1359.
- [Bug findings](archive/bug-findings-f28fc36.md) and the
  [consolidation catalog](archive/consolidation-catalog-f28fc36.md): audits
  of `f28fc36`; every finding is repaired or decided except catalog C13,
  which is in the backlog.
- [Compiler dual-macro campaign](archive/compiler-dual-macro-contract.md#e45-final-source-family-accounting):
  done 2026-09-29 at `82d686e2`; shared grammar projections cover parsed
  source families. The [architecture reference](archive/compiler-dual-macro-architecture.md)
  records retained stage and backend owners, and the
  [aggregate result](archive/compiler-aggregate-source-forms.md) covers Array,
  Map, and String forms.
- [Raw-symbol macros translation](archive/raw-symbol-macros-translation.md):
  done; both repairs and the optional standalone sweep were verified.
- [Publication gate and local workflow](archive/publication-gate-and-local-workflow.md):
  implemented 2026-09-28; private checkpoints and local feature adoption,
  bounded parallel fixtures, and a smaller final publication gate.

- [Try template migration](archive/dual-macro-try-migration.md): done
  2026-09-27; try lowers through one open Macro value on `dev`.
- [Dual macro core support](archive/dual-macro-core-support.md): done
  2026-09-27; macro values, `macro open`, carriers and effects on `dev`.
- [Native `meta` definitions](archive/meta-native-definitions.md): done
  2026-09-25; definition marker and library migration delivered in
  `c3ac95fd` and `56b75433`.
- [REPL fit, status, and runtime surface](archive/repl-fit-and-runtime-surface.md):
  done 2026-09-25; all eight deliveries reached `dev`, and later REPL work
  belongs in `commands/repl`.
- [Meta sequencing](archive/meta-sequencing.md): done 2026-09-25;
  the optional selected-root lifetime proof completed step 4.
- [External commands](archive/external-commands.md): done 2026-09-24;
  framework, packaging, and `graph`/`repl`/`lint` moves delivered through
  `9b31112e`.
- [Meta authoring and coverage](archive/meta-authoring-and-coverage.md):
  done 2026-09-24; nested results came from the explicit meta campaign and
  nine lifetime-sensitive methods were certified.
- [Meta heap objects](archive/meta-heap-objects.md): obsolete; the explicit
  meta campaign delivered meta heap objects (`d0476fe1`, `a9e9ba5d`).
- [Post-merge stabilization](archive/post-merge-stabilization-2026-09-23.md):
  done; delivered as `9b71607f`. The
  [reproducibility record](archive/generated-lisp-reproducibility.md) is
  resolved by binding-ordered loop parameters (`29326dbd`).
- [Internal adoption campaign](archive/internal-adoption-campaign.md): done
  2026-09-24; phases 1-7 delivered, phase 8 closed by the lifetime
  certification. The 44 native-handle operations stay parked until a caller
  exists.
- [Meta lifetime certification](archive/meta-lifetime-certification.md):
  done 2026-09-24 (`1e8de764` through `263fa39b`); nine methods are
  meta-callable and `Var.token` stays private.
- [Indentation dogfooding](archive/indentation-dogfooding.md): done; the
  script tools use `#pragma indent`, converted by `tools/indent-convert`.
- [Indentation syntax](archive/indentation-syntax.md): done; `.xp`,
  `.xp`, and `#pragma indent` select a tokenizer layout pass.
- [Cleanup lowering](archive/emit-cleanup-lowering.md): done; phase 1
  shipped as `68eea0a`, phases 2 and 3 measured and declined 2026-09-24.
- [Explicit meta calls, lifetimes, and computed values](archive/explicit-meta-and-lifetime-campaign.md):
  done; pieces 0-5 delivered through `49a239ec`.
- [Meta values, types, and native records](archive/meta-values-types.md):
  rejected local implementation; session-owned records and a hardcoded native
  bridge failed the requested storage and lifetime contract.
- [Meta recovery](archive/meta-recovery.md): done; delivered as `db86d4b7`.
- [Symlinked home spellings](archive/symlinked-home-spellings.md): done;
  delivered as `0302b1e5` (#70).
- [Meta recovery checkpoints](archive/meta-recovery-checkpoints.md),
  [design](archive/meta-recovery-design.md) and
  [review](archive/meta-recovery-review.md): obsolete; their record wrapper
  and allocation tracker were replaced by native byte storage.
- [September 18 decisions](archive/repository-review-2026-09-18.md#group-10-decided-2026-09-18):
  all nine were decided by Gary, with the original questions and implementation
  outcomes retained. They are not a pending-approval list.
- [September 17 review](archive/repository-review-2026-09-17.md) and
  [September 18 remediation](archive/repository-review-2026-09-18.md): historical
  findings, corrected diagnoses and delivered outcomes.
- [Dogfooding adoption](archive/x2c-dogfooding-remediation.md): bounded campaign
  complete; routine adoption and the linter backlog retain the optional work.
- [Original lowering](archive/x2c-lowers-to-lisp.md),
  [generalization](archive/comptime-x2c-generalization.md) and
  [meta milestones](archive/meta-functions.md): implemented phases, measured
  declines and integration history, superseded as execution plans by current
  meta work.
- [Generated environment](archive/generated-lisp-initial-environment.md),
  [initial algorithms](archive/migrate-initial-lisp-algorithms.md),
  [built-in macros](archive/migrate-builtin-macros.md) and
  [native binding algorithms](archive/migrate-lisp-binding-algorithms.md):
  completed September 20 migrations. Their generated Lisp is not unfinished
  hand-authored migration work.
- [Lowering spike findings](reference/lisp-lowering-spike-findings.md): historical
  design evidence, including the limits of its temporary artifacts.

## Required plan review

Before a plan is presented for approval, end it with a short `## Plan review`
that states:

- which exact facts existing producers or boundaries establish, and whether
  any proposed consumer rechecks those facts;
- what existing code the design deletes or reuses, and why each new helper,
  representation, traversal, cache, or other lasting mechanism is necessary;
- why the resulting source is direct and idiomatic x2c rather than a framework
  imported from another compiler or language; and
- every proposed validator, dedicated diagnostic, and negative fixture, with
  the wrong output, corrupted state, unsafe native crossing, or deliberate
  public behavior it protects. If there are none, say so.

Revise the design before approval when this review finds a duplicated
guarantee or machinery whose only benefit is earlier or more specific failure.
Tests, fixtures, performance work, and green gates may prove a design; they do
not justify keeping the machinery they exercise.

Each planned change also ends implementation with a source review before
the publication proof. That review inspects the completed authored diff for
the same trusted facts, deletion and reuse opportunities, unnecessary
machinery, and idiomatic x2c choices, and fixes what it finds. It is not a new
gate or a report.
