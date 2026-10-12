# plans/

All durable planning lives here. Build tooling and runtime-loaded bootstrap
data stay in `etc/`; ephemeral per-workspace state goes in `.context/`.

- `plans/` - active plans and reference inputs. Each file opens with a
  `> Status:` blockquote, usually several lines: the state, then a note
  saying where the work actually stands. The states in use are `active`,
  `blocked`, `reference`, and `needs author scoping`.
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

Reviewed against `origin/dev` at `cff952cb` on 2026-10-12 by inspecting
changes, source, and delivery history. No build was rerun. Historical branch
and authorization notes describe their original work, not current delivery.
The decisions below preserve unfinished work without authorizing implementation
or adding a gate.

### Partially complete plans: next decisions

| Plan | Delivered work and specific next decision |
| --- | --- |
| [Review remediation, October 11](review-remediation-2026-10-11.md) | Repair batches A-E, the batch F decisions, and cleanup are delivered. Finish the three writing items: canonical forms and legal positions; rewrite ordering, decline, and visibility; compile-time Lisp truthiness, binding, and host `set_global` limits. Decide batch G semantics separately, as listed below. |
| [Language component foundation](language-components-foundation.md) | Selected components and authoring proofs are delivered. Resolve the self-meta function-rule visibility discrepancy before further extraction. Then select or park insertion-site free names/open templates, lexical defer, constructed `with`, and component interface/prelude packaging. Acquired-value cleanup is delivered, not an open decision. |
| [Quotation adoption audit](quotation-adoption-audit-2026-10-03.md) | Type and Param adoption and helper cleanup are delivered. Review remaining structural rebuilds and the 17 autodiff operations individually. Adopt quotations only where they preserve binding and canonical Lists; require a concrete benefit before extending Decl results. |
| [Source consolidation research](source-consolidation-research.md) | Selected prototypes and source changes are delivered. Close the historical campaign, or select one current hypothesis for investigation. Frame-chain sharing is uninvestigated; transaction proposals must be reassessed against the current undo log. Do not dispatch all original hypotheses as one implementation. |
| [Self-expression](x2c-self-expression.md) | Phase 0, language work, and the selected waves are delivered. Select one bounded case: grammar constructors (L5), Lisp string-to-atom (L6), Lisp callables through Func (L7), named protocol methods (L8), pointer-handle Var converters (L11), callback ErrorSlot ownership (L12), generated TagId (L13), or Type-hole _Alignof (L14). Otherwise retire the umbrella as completed waves with reference follow-ups. Reproduce old defect claims on current source first. |
| [Meta continuation](meta-continuation.md) | The operator ledger is delivered. Choose a concrete workload for static Match, prepared formats, scalar Lisp projections, grammar descriptors, Torch generated operations, or numeric policy; otherwise retain these as a reference roadmap. |
| [Harness simplification and messaging](harness-simplification-and-messaging.md) | Repository repairs and the messaging pilot are delivered. Decide whether to pursue the three external runtime reports or retain documented limitations. Use a real PR for the messaging trial only when that work and its messages are authorized. |
| [Public release workflow](public-release-workflow.md) | Candidate and staging work is recorded as delivered. Choose the production baseline and recovery procedure, then the candidate version and promotion destination. This audit does not verify current deployment state or authorize promotion to main. |
| [C on-ramp](x2c-c-on-ramp.md) | Parser/corpus work is delivered. Implement the four worked adoption examples in section 4b2 above the fold, or retire that remaining website proposal. |
| [Lint and format](x2c-lint-and-format.md) | Phases 0-7 and experimental lint are delivered. Choose whether to implement phase 8 List findings and compiler consumption during builds, or park it. Decide editor integration and distribution only if lint will ship. Any added recurring build cost needs Gary's approval. |
| [Scripting ports](x2c-scripting-ports.md) | Extensionless tools and documentation checks are delivered. Select a bounded fixture, example, probe, benchmark, or graph port. Treat `release-candidate.py` as separate release-safety work; the old release workflow target needs reassessment. |

Recommended disposition: finish the three remediation writing items and resolve
the foundation visibility contradiction first. Retire completed umbrella
campaigns with their evidence; select new bounded work only where a current
caller or workload establishes its value.

### Unstarted delivery and semantic choices

[Ordinary switch over String](string-switch.md) has a private implementation
on `independent-case-design`, but no shipped feature on dev. Decide whether to
review and resume that implementation against current quotation and `add_early`
APIs, or defer the feature. Its next step is not a fresh implementation from
an empty baseline.

The remediation plan's batch G is a decision list, not eleven approved repairs:

| Choice | Decision needed |
| --- | --- |
| Cross-tag Var equality and ordering | Define conversion and comparison rules together with hash, Map, and sorting consistency. |
| Expression rewrite visibility | Resolve the foundation discrepancy through the existing visibility owner before adding state. |
| General evaluation order | Inventory unresolved operations before promising one universal ordering rule. |
| Wide indices | Choose one conversion boundary that prevents incorrect narrowing, and decide compatibility for oversized indices. |
| Non-List Var match | Decide whether nil coercion or rejection is the public contract; align the guide and implementation. |
| Class unboxing and scalar sibling typedefs | Decide the supported conversions before expanding the advertised surface. |
| Module mode and conditional entry | Retain conservative behavior or commission full native entry semantics as a feature. |
| Foreign-thread embedding | Define process initialization and thread initialization/teardown separately. |
| Platform ABI and stability | Document current limits or commission new C11 AST ABI/platform support. |
| Numeric shorthands | Decide what `u128`/`i128` mean where they currently map to 64-bit types. |
| Expanded recurring validation | Retain existing gates unless a cost-neutral replacement is approved. |

[Module blocks](archive/module-blocks.md) are delivered and already archived.
Two follow-ups need a separate decision: repair included-module diagnostic
location replay through the existing mapping owner, or document the limitation;
and retain the companion-path spelling restriction, or normalize paths before
checking containment. The diagnostic location defect was reproduced before
this source-only refresh; the refresh did not rerun its executable probe.

### Reference inputs and dormant proposals

These records do not describe approved, unstarted implementation campaigns.

| Record | Disposition or decision |
| --- | --- |
| [Compiler kernel analysis](compiler-kernel-minimal.md) | Reference for component extraction. Select a remaining migration only after foundation semantics are settled. |
| [Compiler ownership investigation](compiler-ownership-investigation.md) | Seven bounded candidates and a field inventory; no compiler refactor approved. Select one current ownership question or retain the assessment. |
| [Lifetime proof follow-up](lifetime-proof-followup.md) | Selected-root audit is delivered. Indexed borrows, container values, native handles, and iterator callbacks remain optional extensions without a commissioned workload. |
| [SDK and system macros](macro-sdk-and-system-macros.md) | Located errors are delivered. Choose whether node-located warnings or enum consumers justify another bounded change. |
| [Meta follow-ups](meta-followups.md) | Recorded `off_t`/`time_t` and atomic aggregate limits remain reference constraints. The packing proposal was withdrawn. |
| [Prepared formats](prepared-format.md) | Feasibility research is complete. Defer a FormatPlan API until a real repeated-format workload justifies it. |
| [Overengineering candidates](overengineering-candidates.md) | Reference ledger used by forensic skills. Its remaining `comptime.x` lowering candidate is obsolete because that source was removed; do not dispatch the old row. |
| [Harness evidence](harness-evidence-2026-10-05.md) | Supporting reproductions for the external runtime decisions above. |
| [Remediation evidence](review-remediation-evidence-2026-10-11.md) | Dated repair and analysis evidence, not a second task queue. |
| [Remediation language ledger](review-remediation-language-ledger-2026-10-11.md) | The 181 rows are a coverage ledger, not 181 unstarted tasks. Use the main plan's remaining writing and semantic choices. |
| [Explicit meta backlog](archive/explicit-meta-and-lifetime-campaign.md#backlog) | Parked compound selectors, meta function-handle assignment, wide-scalar REPL coverage, destructuring beside cleanup, and heap limits. Recheck current behavior before selecting one. |
| [Scoped memoization](archive/unit-initialization-and-assembly.md#scoped-memoization-deferred) | Require a repeated substantial computation, its complete inputs, and a lifetime owner before starting. |
| [Consolidation C13](archive/consolidation-catalog-f28fc36.md#c13-larger-lifetime-sharing-locate-overlap-without-pretending-equivalence) | Investigate actual overlap between lifetime summary and flow production before proposing shared machinery. |

### Decisions and completed records

Archived 2026-10-12 after checking delivery on dev:

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
  delivered as `610c52f5`.
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
