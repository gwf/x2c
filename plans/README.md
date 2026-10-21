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

Consolidated with Gary's decisions on 2026-10-12, against `origin/dev`
`71e933b0`. Source and delivery history were inspected; no build was rerun.
Each remaining change has one owning plan. The descriptions below record scope
and next actions, not implementation completed by this documentation update.
Earlier question lists and branch restrictions are historical.
The [merged repair notes](review-remediation-2026-10-11.md#repairs-merged-during-planning-recorded-2026-10-12)
record the additional literal, cleanup, and post-module diagnostic repairs.
Their impact was reviewed against `2b5ee957`; no executable reproduction was rerun.

### Decided work

| Owning plan | Accepted behavior or deliverable | Next action |
| --- | --- | --- |
| [Build CLI defaults](build-cli-defaults.md) | Expose existing defaults, create translation directories, reuse retained builds, default multiple object outputs, restore native `-o`, and use the correct compiler in examples. | Implemented at `c91d7ed43`; CLI checks pass. Complete delivery using Gary's exception for the pre-existing stage-1 region warning. |
| [Review remediation: writing](review-remediation-2026-10-11.md#writing-and-supported-features) | Explain legal source forms, rewrite behavior, and compile-time Lisp behavior. Maintain the factual support list. | Finish the three book explanations with accepted examples. |
| [Language component foundation](language-components-foundation.md#recorded-decisions) | Rules see developer-written expressions and program meta definitions. Compiler-inserted support calls stay outside program rules. Templates retain author bindings. Constructed `with` behaves like handwritten `with`. | Delivered: the support-call and author-binding boundaries in PR #193 on 2026-10-13; constructed `with` already behaved as decided. The plan's [open list](language-components-foundation.md#open-needing-research-before-a-decision) holds the remaining items. |
| [Repository review](repository-review-2026-10-12.md#execution-log) | Decisions 1-11 recorded on 2026-10-12: numeric comparisons, 32-bit indices, non-List match, Var to String, component dispatch, cleanup labels, self-meta, SDK, seams, AR-3, and deferrals and hygiene. | Carried out in ten batches through `4b387196` on dev, plus hygiene. No delivery is recorded for the section D cleanup backlog, the section E documentation drift, or the typed list views that batch 10 left as a follow-up. |
| [Quotation adoption](quotation-adoption-audit-2026-10-03.md#typed-_alignof-and-scalar-generator-cleanup) | `_Alignof($type)` accepts a typed Type hole and emits target C alignment. Simplify the scalar generator while preserving exact native behavior. | Deferred past the cleanup phase (repository review decision 11). Then pair the missing quotation form with its current scalar caller. |
| [Lint and format](x2c-lint-and-format.md#current-remaining-work-2026-10-12) | Finish already-approved structured List findings and compiler consumption. Keep lint optional. | Continue phase 8 and the existing optional editor workflow; add no recurring gate. |

The [repository review](repository-review-2026-10-12.md#decisions-recorded-2026-10-12)
delivered the remediation decisions for numeric comparisons, non-List match,
Var-to-String crossings, and the module follow-ups through `3db5216c` and
`c397213b`. Its decisions govern where the earlier remediation text differs:
indices are 32-bit `int` (decision 2), a non-List Var subject reaches
`default` (decision 3), explicit Var readers raise `<no-convert>` for another
tag (decision 4 and batch 10), and a function rule does not rewrite the
compile-time copy of a self-meta definition (decision 7). The same review
deferred String `switch` and typed `_Alignof` past the cleanup phase.

A practical starting order is the book explanations and then the foundation
boundaries. This order is a recommendation, not another planning or
validation requirement.

### Candidates, not selected implementation

| Candidate | Condition for pursuing it |
| --- | --- |
| [Generate TagId from its rows](quotation-adoption-audit-2026-10-03.md#candidate-generate-tagid-from-its-rows) | Remove real duplication while preserving every numeric ID and avoiding new meta dependencies for ordinary Var users. Lower priority. |
| [Expand lifetime proof](lifetime-proof-followup.md#current-disposition-2026-10-12) | Name a current program and reproduce its actual obstacle before extending the delivered selected-root audit. |

### Reference material

These files supply evidence or describe future operations. They do not create
additional implementation tasks or questions for Gary.

| Record | Use |
| --- | --- |
| [Compiler kernel](compiler-kernel-minimal.md) | Evidence for a specifically selected component extraction. |
| [Compiler ownership](compiler-ownership-investigation.md) | Bounded ownership investigation and field inventory; no broad refactor commissioned. |
| [Compiler ownership evidence](reference/compiler-ownership-evidence.md) | Static field inventory at `548b381f`, the companion to the ownership investigation. |
| [SDK and system macros](macro-sdk-and-system-macros.md) | Delivered located errors and historical warning/enum ideas; require a current caller for new work. |
| [Meta follow-ups](meta-followups.md) | Recorded native type and aggregate constraints; packing proposal withdrawn. |
| [Prepared formats](prepared-format.md) | Completed feasibility work; a real repeated-format workload is needed. |
| [Overengineering ledger](overengineering-candidates.md) | Forensic reference. The removed `comptime.x` candidate is obsolete. |
| [Public release workflow](public-release-workflow.md) | Future release operation and delivered staging evidence. This cleanup does not select a production version or authorize promotion to main. |
| [Harness evidence](harness-evidence-2026-10-05.md) | Dated external runtime incidents, not x2c feature requirements. |
| [Remediation evidence](review-remediation-evidence-2026-10-11.md) | Dated repair and reproduction evidence. |
| [Remediation language ledger](review-remediation-language-ledger-2026-10-11.md) | Coverage evidence, not 181 tasks; current decisions belong to the remediation plan. |

The recorded decisions withdraw the foreign-C-thread API, CPP/module guarantees,
u128 feature claim, blanket typedef restrictions, lexical defer, packaging
redesign, and expanded recurring gates. They first withdrew generic unboxing
checks; repository review batch 10 later made the explicit Var readers, such
as `.list()` and `.map()`, raise for another tag. The closed self-expression campaign retains other unsupported feature proposals as history.
Shared ErrorSlot is dropped because it does not simplify the existing callback
owners. Unselected consolidation, formatting, Match, descriptor, Torch, numeric
table, and arbitrary script-port experiments remain reference material.

### Decisions and completed records

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
  [foundation plan](language-components-foundation.md) and the
  [kernel catalog](compiler-kernel-minimal.md).

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
