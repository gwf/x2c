---
name: improve-x2c-agent-process
description: >-
  Review or improve x2c's repository agent instructions, skills, Conductor
  prompts, commands, defaults, or validation workflow. Use for dedicated
  agent-process work prompted by session evidence, changed development
  practices, instruction bloat, routing failures, or a strategic review.
  Do not invoke during ordinary product work merely because it produced a
  lesson.
---

# Improve the x2c agent process

Improve repository guidance and tools for the requested workflow. Start from
a reported failure, a changed development practice, or a strategic review.
Completion follows the request: a review provides findings and recommendations;
an implementation changes and validates the relevant agent interface.

## Understand current work

Read the instructions, skills, prompts, and tools involved. For reported
failures, inspect raw session evidence and identify the observed failure, the
contributing action, and behavior to preserve. For strategic work, compare
current guidance with the intended workflow and representative tasks.

Use measurements when they answer that question. `tools/harness-metrics.py`
summarizes local Claude and Codex transcripts; compare agents separately
because their interfaces expose different actions. `tools/repo-metrics.py`
measures repository and agent-facing text size. Record a relevant baseline.

When Gary's reported incidents are relevant, `tools/agent-failure.py list`
and `plans/agent-failures.md` locate captured evidence. Read that evidence;
index rows and counters alone do not establish what happened. Preserve raw
history outside the repository.

## Change the existing guidance or tool

Prefer a clearer command, useful example, or better default to another rule.
Put repository-wide instructions in root or nested `AGENTS.md`, task workflows
in skills, product facts in source or the book, and deterministic sequencing
in existing scripts or Make targets. Link to the source of a fact and remove
competing copies. [agents/README.md](../../README.md) routes to current skills
and references.

Keep the requested problem in control. For an open-ended review, present
supported options and a recommendation. For authorized implementation, resolve
routine choices and complete the change; ask only when a consequential choice
is unresolved. Ordinary product work does not edit shared guidance merely
because it suggests a lesson.

Use root process limits for recurring requirements. Keep evaluator rules, raw
evidence, model configuration, and task definitions stable when comparing
behavior; changing the expected result or budget does not prove improvement.

## Verify the requested result

Check references, discovery, metadata, and affected tools. For workflow
changes, use fresh isolated planning sessions with representative direct,
indirect, and nonmatching requests. Keep prompts neutral. Test the conditions
the observed failure needs; a fresh short session cannot establish behavior
that depends on a long history. Use the relevant corpus when necessary and
state the limits of the evidence.

Keep these experiments specific to the change rather than adding recurring
product gates. For implementation, review and fix the authored diff and follow
root validation and delivery instructions. Update incident status only when
the validated change actually resolves the corresponding report.

Report the requested result and evidence: recommendations for a review, or the
changed agent behavior and validation for implementation. If evidence supports
no useful change, say so; metrics or bookkeeping alone do not constitute an
implemented improvement.
