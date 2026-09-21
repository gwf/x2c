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

Reviewed against dev through `144a833d` on 2026-09-20. A historical plan's
original branch, baseline and authorization notes are evidence for that work;
its opening status and this index distinguish them from current execution.

### Current work

- [Public release workflow](public-release-workflow.md): active in the Dev
  Staging Workflow task. Account activation and production decisions remain;
  source files alone do not establish that deployment is complete.
- [Meta authoring and coverage](meta-authoring-and-coverage.md): source-code
  template calls, representable literal results, and the API inventory are
  implemented. Mutable container results, iterator state, and full fold parity
  remain bounded follow-ups. The older
  [meta milestones](archive/meta-functions.md) record the preceding baseline.
- [REPL fit, status, and runtime surface](repl-fit-and-runtime-surface.md):
  terminal UX, live statistics, and REPL-only output are implemented;
  standard-library and host exposure remain undispatched recommendations. The
  lexical-scope repair to the literate example shipped in `144a833d`.

### Open backlog and scoped follow-ups

| Record | What remains |
| --- | --- |
| [Generated Lisp reproducibility](generated-lisp-reproducibility.md) | Low-priority investigation of fresh-home generated names; no demonstrated semantic failure. |
| [SDK and system macros](macro-sdk-and-system-macros.md) | Captured-code diagnostic locations and enum consumers; the removed varops Lisp file is no longer work. |
| [Cleanup lowering](emit-cleanup-lowering.md) | Optional, unscheduled phases 2-3; phase 1 already shipped. |
| [Lint and format](x2c-lint-and-format.md) | Needs author scoping; includes opportunistic declaration grouping from the completed dogfooding campaign. |
| [Header collection gaps](x2c-header-collection-gaps.md) | Needs author scoping; retained unresolved cases were last reproduced September 17. This cleanup does not claim a new compiler probe. |
| [Tooling ports](x2c-scripting-ports.md) | Remaining tool ports and consumer-driven library additions after the delivered regex/diff/script work. |
| [C on-ramp](x2c-c-on-ramp.md) | Landing-page adoption examples; the parser/corpus work already shipped. |
| [Var-tags experiment](archive/meta-functions.md#parked) | Parked until a measured approach meets the recorded translation-cost condition. |

An entry here preserves remaining work; it does not dispatch it or add a gate.
Production promotion remains separately authorized under the release workflow.

### Decisions and completed records

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
