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

Use a phased structure, each phase carrying `Status: complete (date)` when it lands,
with measured baselines recorded in the plan itself (e.g. test counts before
and after). A plan that is finished says so inline — nobody should have to
diff the tree to learn a plan's fate.

An archived rejection records the exact implementation, compiler capability,
and evidence measured at that time. It does not create a permanent rule against
the candidate family. New syntax, projections, compilation behavior, source
structure, or measurements may justify a new prototype. Treat old phrases such
as `do not reopen` or `no other candidate` as historical unless current
`AGENTS.md`, agent guidance, or an active plan restates the exact restriction.

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

Each planned pull request also ends implementation with a source review before
the publication proof. That review inspects the completed authored diff for
the same trusted facts, deletion and reuse opportunities, unnecessary
machinery, and idiomatic x2c choices, and fixes what it finds. It is not a new
gate or a report.
