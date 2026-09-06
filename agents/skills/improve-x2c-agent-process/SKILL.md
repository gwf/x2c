---
name: improve-x2c-agent-process
description: >-
  Materially improve x2c's repository agent instructions, skills, Conductor
  prompts, commands, defaults, or validation workflow from actual session
  evidence. Use only for dedicated agent-process work, especially repeated
  agent errors, instruction bloat, skill routing failures, or wasteful
  recurring commands. Do not invoke during ordinary product work merely
  because that task produced a lesson.
---

# Improve the x2c agent process

Make agents more capable by giving them less, better guidance and a simpler
interface. Optimize for correct product work and beautiful code, not for more
rules, validators, reports, or visible harness activity.

The result is a material improvement to an existing agent interface. Metrics,
incident status, plans, reports, and explanations may support or record that
improvement; none of them is the improvement.

## Start from the reported failure

Inspect current instructions, skills, prompts, build targets, and the raw
session evidence behind the reported problem. Separate:

- the final observable failure;
- the agent action that caused or failed to prevent it;
- the instruction, skill, tool, or interface that influenced that action; and
- passing behavior the change must preserve.

The user's reported failure controls which candidates are relevant. Do not
substitute an easier measurement, evidence-tool defect, table update, or
adjacent process problem. Evidence tooling is the work only when the user
named it or it prevents evaluating the reported failure.

Measure a pattern when the available measurements bear on it.
`tools/harness-metrics.py` summarizes local Claude and Codex session
transcripts: skills invoked, build targets run, broad gates repeated with no
intervening edit, push form, and rework. Compare agents separately before
combining their rates; their tool interfaces expose different actions.
`tools/repo-metrics.py` records tree size and the agent-facing text alongside
it. Compare against a baseline recorded for the work being reviewed.

`plans/agent-failures.md` indexes the failures Gary reported himself, with the
captured session evidence at the path each row names. The capture command
appends the row itself; compare `tools/agent-failure.py list` with the index
when reported failures are relevant so an older missed append cannot hide
evidence. Read the evidence, not the row. These are the sessions the counters
call clean: a claim that was false when it was made, an instruction ignored,
work asserted that was never done.
Metrics see what agents did; this log is the only record of what they said.

Prefer a repeated pattern across independent sessions. Two incidents of the
same shape from different sessions already are that pattern. A single incident
justifies a durable guard only when its consequence is destructive and the
guard is narrow, such as preventing a push to the wrong branch.

Prefer changing a name, command, or default over adding a paragraph. Measured
on this repository, renaming Make targets moved old spellings from 82% to 9%
and requiring an explicit push refspec moved source-only pushes from 100% to
16%, while a paragraph asking agents to justify a repeated gate left the
behavior slightly worse than before. A rule that asks for judgment at the
moment the wrong action is easiest is the weakest instrument available.

Do not turn one difficult task, one model mistake, or a task-specific product
fact into permanent repository process.

## Find the smallest owner

Map the failure to one existing surface:

- root or nested `AGENTS.md` for always-applicable rules and permissions;
- a skill for a repeatable task workflow;
- `docs/` or source for language and product truth;
- a Make target or script for fragile deterministic sequencing;
- a Conductor action prompt for the corresponding UI action.

Update one owner and delete or shorten competing copies. Prefer routing to
relevant context over requiring every agent to read every reference. Keep
detailed facts discoverable in their current source instead of copying them
into a skill.

The evaluator, permission rules, session evidence, and model configuration
remain outside the editable proposal whenever possible. Never improve a score
by weakening checks, changing the task, raising the budget, or exposing the
expected answer.

## Choose work that fixes it

When the user names a failure, candidate, or authorized action, keep it in
control and proceed within that authorization. Do not introduce another
approval round unless a missing choice would materially change the result.

When the user invokes this skill without naming the problem to improve,
develop two to four evidence-backed candidates, recommend the strongest one,
and pause for selection. A candidate is an actual change to an instruction,
skill, prompt, command, default, or existing validation workflow. Metrics,
incident reconciliation, a plan, and a report are not candidates.

For each candidate, state the observed failure, the exact surface to change,
the expected improvement, and the passing behavior most at risk. Default to a
net reduction in always-loaded text or recurring commands.

The root `AGENTS.md` "Process Ceiling" governs anything that adds a recurring
requirement. Also show why the existing mechanism cannot protect the behavior.

Ordinary product tasks do not edit shared agent guidance. They may report a
lesson; this dedicated review decides whether evidence supports a durable
change.

## Validate without creating another gate

Check instruction and skill discovery mechanically. For a material workflow
change, use fresh isolated planning sessions on representative tasks with the
minimum task-local context. Include direct triggers, indirect triggers, and a
request that must not select the skill. Do not leak the desired design into
the test prompt.

A fresh session cannot test a failure that needs a long one. `#282` passed
this way and failed in production, because the reply it was fixing only goes
wrong when the agent has a session's worth of work already in it.
Before trusting a forward test, name the condition the failure needs and
check the test reproduces it; when it cannot, measure the real corpus instead
and say that is what you did.

Accept a change only when it addresses the observed pattern without degrading
the representative tasks or weakening product verification. Keep this
forward-test specific to the harness change; never add it to `precommit`,
`check`, `agent-pr-check`, or ordinary product workflow.

Only after a material change is implemented and validated, name the rows in
`plans/agent-failures.md` it actually settled and move those rows off `open`.
Do not close rows or repair counters to manufacture an output for this skill.
If publishing, put what became simpler, the recurring work removed, the
evidence, validation, preserved behavior, and rejected candidates in the pull
request body. Gary gets what changed and what he has to approve, in the reply
the root `AGENTS.md` Communication section describes. Preserve raw session
history outside the repository; commit only the concise accepted guidance.

The work is complete only when the agent interface changed and that change was
validated. When the evidence supports no durable improvement, say so and
leave the bookkeeping untouched; do not report the review itself as an
improvement.
