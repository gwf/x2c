# plans/

All durable planning lives here. Build tooling and runtime-loaded bootstrap
data stay in `etc/`; ephemeral per-workspace state goes in `.context/`.

- `plans/` - active plans and reference inputs. Each file opens with a
  `> Status:` blockquote, usually several lines: the state, then a note
  saying where the work actually stands. The states in use are `active`
  and `reference`.
- `plans/reference/` - dated evidence and unselected research inputs.
- `plans/archive/` - finished plans. The same blockquote, recording the
  outcome, its date, and the commit or PR that closed the plan. Write
  `done`, `rejected`, `obsolete`, or `retired`. Never delete a plan; archive
  it with its outcome. Archived and reference workflow restrictions record
  the authorization that applied at the time; current work follows the root
  `AGENTS.md`.

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

Completed deliveries are archived below. Remaining implementation questions
and conditional candidates have explicit owners. Historical measurements
remain evidence for their named revisions; this index does not commission
deferred work or main promotion.

### Active work

| Owning plan | Remaining scope | Next action |
| --- | --- | --- |
| [Deep review remediation, second pass](deep-review-remediation-2026-11-02.md) | Batch A repairs and batch B cleanup; all eight decisions approved. | Complete combined review and direct publication validation. |
| [Deep review remediation](deep-review-remediation-2026-11-01.md) | Only the final "Still carried" findings; batches A, B, C, and the bug batch are published through `dbcb6c347`. | Reproduce each selected follow-up; preserve the superseding invocation-time iterator callback rule. |
| [Review follow-ups](review-followups-2026-10-31.md) | Script LSP offsets, native-module probe, lint tiers, attribute macros, Linux dependency identities, CPP overflow, example instructions, and documentation gate scope. | Start each selected repair with its named reproduction; do not reopen completed campaigns. |
| [Language-reference writing](language-reference-writing.md) | Remaining rewrite explanation and runtime Lisp truthiness/host-limit coverage. | Preserve delivered AST catalog and binding explanations; fill exact missing coverage. |
| [Structured lint findings](x2c-lint-and-format.md) | Approved optional List output and compiler consumption. | Implement that interface when selected; preserve experimental distribution. |

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
