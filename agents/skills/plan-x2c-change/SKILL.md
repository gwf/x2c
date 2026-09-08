---
name: plan-x2c-change
description: >-
  Answer questions about current x2c behavior with source and probes, or
  decide and record a change before implementation starts. Use when a
  request asks how the current design works, names a goal but not a design,
  or needs work scoped into pull requests. A behavior question needs an
  answer, not a change plan. For an already-decided implementation, use
  execute-x2c-plan.
---

# Plan an x2c change

Answer the question or decide one coherent change using current source,
working examples, and focused evidence. Investigation and planning do not
authorize implementation.

## Establish the result

Read the request and its named documents, relevant source and tests, and the
book pages that specify the behavior. State the observable result and what
must remain compatible. If the existing implementation already meets the
request, demonstrate that and report it.

For a question about current behavior, finish with the answer, source or
probe evidence, and any remaining uncertainty. Do not invent a change or
write a durable plan merely because answering requires investigation. The
plan section below applies when proposing a change.

Resolve discoverable questions from the repository. Ask about consequential
choices the request leaves open, such as public behavior or caller
obligations. Routine implementation choices can follow existing code.

## Establish feasibility

Use a focused probe when it resolves an uncertainty: translation, generated-C
inspection, native compilation, runtime behavior, or a meaningful before/after
measurement. Keep temporary probes outside tracked source. Record what the
probe establishes and what it leaves uncertain. If it falsifies the approach,
revise the design or recommend stopping.

For AST work, use
[the Match guide](../../replacing-manual-ast-walks-with-match.md)
to identify the canonical input, structural pattern or template, and ordinary
operation that binds, types, places, or emits it. The optional
[source graph commands](../../../tools/x2c-graph/README.md) `flows` and
`compare` can establish parsed-source paths; they do not establish semantic
equivalence or the absence of runtime paths.

Compare proposed machinery with deletion, reuse, and composition of existing
x2c features. Trace proposed checks to the code that establishes the relevant
fact. Apply the root validation rule: an earlier or more specific failure
alone does not justify another validator or negative fixture.

## Record a decision-complete plan

Follow [plans/README.md](../../../plans/README.md). Describe the result,
settled choices, connected implementation, compatibility, and observable
validation clearly enough for a fresh implementing session. Include counts or
performance measurements when they decide the design; use coherent separate
changes only when the work needs them. A PR is a delivery choice, not the unit
of every design.

End with the required short design review. Make the last implementation step
review and fix the completed authored diff before publication validation.

The deliverable is the recommended design, evidence, and any consequential
question requiring Gary's decision. A planning-only request ends there. If the
user already requested implementation, proceed once its decisions are settled
using `execute-x2c-plan`; a separate session or approval round is unnecessary
for routine choices.
