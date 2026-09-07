---
name: plan-x2c-change
description: >-
  Decide and record the design for one x2c change before implementation
  starts. Use when a request names a goal but not a design, when a question
  about the current design needs an answer backed by a probe, or when work
  must be scoped into pull requests. Do not use to carry out a plan whose
  decisions are already recorded; use execute-x2c-plan for that.
---

# Plan an x2c change

Decide one coherent change using current source, working examples, and focused
evidence. A planning or design-review request produces a recommendation and a
plan; it does not authorize implementation.

## Establish the result

Read the request and its named documents, relevant source and tests, and the
book pages that specify the behavior. State the observable result and what
must remain compatible. If the existing implementation already meets the
request, demonstrate that and report it.

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
operation that binds, types, places, or emits it. `x2c-graph flows` and
`x2c-graph compare` can establish parsed-source paths; they do not establish
semantic equivalence or the absence of runtime paths.

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
