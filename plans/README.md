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

Reviewed against the stabilization candidate on 2026-09-23. A historical
plan's original branch, baseline and authorization notes are evidence for
that work; its opening status and this index distinguish them from current
execution.

### Current work

- [Meta lifetime certification](meta-lifetime-certification.md): active.
  Replaces adoption phase 8; certifies ten methods for meta code through
  the region table, decided September 24, 2026.
- [Post-merge stabilization](post-merge-stabilization-2026-09-23.md): done;
  delivered as `9b71607f`. The
  [reproducibility record](generated-lisp-reproducibility.md) retains the
  earlier Lisp regeneration failure and the repaired result.

- [Internal adoption campaign](internal-adoption-campaign.md): phases 1-6
  are complete, and phase 7 moved the value operations to `meta`
  prototypes. Its compiler-binding half needs a design; phase 8 continues as
  meta lifetime certification.
- [Public release workflow](public-release-workflow.md): active in the Dev
  Staging Workflow task. Account activation and production decisions remain;
  source files alone do not establish that deployment is complete.
- [Meta authoring and coverage](meta-authoring-and-coverage.md): source-code
  template calls, representable literal results, and the API inventory are
  implemented. The represented-operation campaign is complete; the remaining
  methods are classified as excluded contracts, explicit adapters, defects, or
  dependencies of the separate meta-capable protocol and lifetime-certification
  work. Generalized `meta` declarations landed as `db86d4b7` through the
  [meta recovery](archive/meta-recovery.md). The older
  [meta milestones](archive/meta-functions.md) record the preceding baseline.
- [Meta follow-ups](meta-followups.md): scalar-ledger cleanup and measurement
  of numeric Func's remaining per-call frame cost are open; the small-defect
  and system-header investigations record their outcomes. Meta-capable
  protocols, lifetime certification and native extensions retain their
  separate design and implementation status.
- [REPL fit, status, and runtime surface](repl-fit-and-runtime-surface.md):
  terminal UX, live statistics, and REPL-only output are implemented, and
  scalar math is already callable; exposing Json, Diff, and Path text
  operations (about 20 `.x` lines) awaits Gary's decisions. The
  lexical-scope repair to the literate example shipped in `144a833d`.

### Open backlog and scoped follow-ups

| Record | What remains |
| --- | --- |
| [SDK and system macros](macro-sdk-and-system-macros.md) | Captured-code diagnostic locations and enum consumers; the removed varops Lisp file is no longer work. |
| [Lint and format](x2c-lint-and-format.md) | Needs author scoping; includes opportunistic declaration grouping from the completed dogfooding campaign. |
| [Meta heap objects](meta-heap-objects.md) | Needs author scoping; bind the Scope allocator for meta bodies, extend the region pass for `free` and `realloc`, and support heap classes at compile time. |
| [Tooling ports](x2c-scripting-ports.md) | Extensionless tool names, the llms.txt generator, the documentation sample checks and `tools/check-docs` are delivered; release, gate and compiler-backed ports are separately sequenced. |
| [C on-ramp](x2c-c-on-ramp.md) | Landing-page adoption examples; the parser/corpus work already shipped. |
| [Explicit meta campaign](archive/explicit-meta-and-lifetime-campaign.md#backlog) | Parked compound-selector owner, direct function-handle assignment in meta bodies, a REPL test for wide scalar globals, destructuring beside a cleanup, and three small heap limits. |
| [Var-tags experiment](archive/meta-functions.md#parked) | Parked until a measured approach meets the recorded translation-cost condition. |

An entry here preserves remaining work; it does not dispatch it or add a gate.
Production promotion remains separately authorized under the release workflow.

### Reference audits

- [Consolidation catalog](consolidation-catalog-f28fc36.md): 13 independent
  cleanup candidates with paired source ranges and deletion boundaries.
- [Bug findings](bug-findings-f28fc36.md): eight reproduced baseline defects,
  with portable probe sources, historical results and later repair
  dispositions, separate from cleanup.

Both reports audit `f28fc36` (2026-09-22). The bug report now also links
campaign outcomes; the original observations do not describe later
`dev` by themselves or approve every proposed design.

### Decisions and completed records

- [Indentation dogfooding](archive/indentation-dogfooding.md): done; the
  script tools use `#pragma indent`, converted by `tools/indent-convert`.
- [Indentation syntax](archive/indentation-syntax.md): done; `.xp`,
  `.xpmacro`, and `#pragma indent` select a tokenizer layout pass.
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
