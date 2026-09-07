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

Produce one decided design, small enough to land as a single pull request,
grounded in the current source and proved by a probe. Stop for approval before
implementation.

The root `AGENTS.md` "Project Priorities" governs what a good design is. This
skill adds only how to establish the goal, how to prove a design cheaply, and
what the recorded plan must contain.

## State the observable goal

Read the request, every plan or specification it names, and the source and
tests that own the behavior today. State the observable result in ordinary
words. If current source already provides it, say so and stop; that answer is
the deliverable.

For a language or library semantics change, also read `docs/AGENTS.md` and the
current pages under `docs/` that own the behavior. Record their required edits
in the plan. Archived plans and agent guidance may explain a decision, but
they do not replace the book as the user-facing authority.

If the request does not identify the behavior being changed, say what is
missing. Do not invent a task or substitute a repository survey for a goal.

Do not escalate a question whose answer has no consequence. A decision that
changes no code, no interface, and no measurement is not a decision.

## Prove the design with a probe before proposing it

Reading the code tells you what is there. A probe tells you whether your
design works and what it costs. Prefer a probe every time.

Copy the affected sources to `/tmp`, apply the change mechanically, and
measure. A probe that translates every affected module, compiles the result,
and records a before-and-after number is worth more than any amount of
prose, and it usually costs minutes.

Record what the probe measured: counts before and after, build time, output
size, generated lines. Those numbers belong in the plan.

When a probe falsifies the design, that is the plan's most valuable result.
Record the falsification and propose the alternative or recommend stopping.

## Scope the work to one pull request

A plan is decided when someone else could execute it cold, in a fresh
session, without asking a question. Size each unit so that one pull request
carries one coherent, reviewable change with its own proof.

Splitting work into more pull requests is nearly free. Batching several into
one session is not: it produces rebases against a moving `main`, resets, and
force-pushes. When a design needs several units, write them as a sequence in
one plan, each with its own boundary and its own status, and expect each to
be executed in its own session.

## Challenge the design before recording it

Trace every proposed check from the value's producer to its consumer, and name
the exact fact that producer or boundary establishes. Do not plan a second
traversal, copied state, dedicated diagnostic, or negative fixture merely to
reject the same bad input earlier or with different wording. A new check needs
a concrete case where the existing path would otherwise accept wrong output,
corrupt state, cross an unsafe native boundary, or violate deliberate public
behavior.

For compiler AST work, read
`agents/replacing-manual-ast-walks-with-match.md` and begin with the canonical
AST the producer already creates. State whether the structural change can be
expressed with a Match pattern and literal output template, then name the
ordinary semantic operation that will bind, type, place, or emit the result.
Parsed source, macro construction, compile-time Lisp, and transforms should
not acquire parallel semantic paths for the same AST. Keep a separate path
only for work that is genuinely primitive or operational, such as token
parsing, scope mutation, type resolution, cleanup, ABI handling, diagnostics,
or emission order.

When reachability is uncertain, use `x2c-graph flows` to follow one structural
result into one semantic consumer and `x2c-graph compare` to compare supplied
entries against supplied operations. These commands prove exact parsed-source
paths and expose unresolved boundaries; they do not prove semantic
equivalence or absence of a runtime path.

Account for what the design adds to the hand-authored source, including new
helpers, representations, caches, metadata, and exceptional paths. Compare it
with deleting code, extending an existing owner, or composing existing x2c
features. If validation needs optimization or caching to meet a performance
fence, first test whether the validator should be deleted.

Read the relevant source guidance before calling the result idiomatic. The
plan must explain why its source shape belongs in x2c, not merely why it is a
familiar compiler technique or why its tests pass.

## Write the plan as a log

Follow `plans/README.md`. The plan is in `plans/`, opens with the
one-line `> Status:` header, and carries measured baselines inline so nobody
has to diff the tree to learn what changed or what a phase was worth.

Name exact counts before work starts. "223 `$error.fallback` decorators on
shared literal causes, PR 2 covers 182 of them" is a plan. "Reduce error
handling boilerplate" is not.

State which decisions are settled, so the executing session does not
relitigate them.

End every plan with the `## Plan review` required by `plans/README.md`. Revise
the design until that review passes; do not leave concerns for the executor or
Gary to discover after approval.

Make the last implementation step for each pull request the source review
required by `plans/README.md`, before its publication proof. It reviews and
fixes the completed authored diff; it does not add a gate or produce a report.

Record a rejection in the same form. An archived rejection preserves the
implementation, capability, and measurement that applied at that time; it is
not a permanent rule against the idea.

## Stop for approval

Implementation is a separate step and usually a separate session. Present the
design, the probe's numbers, the pull-request boundaries, the completed plan
review, and the passing behavior most at risk. Ask for approval and stop.

Do not begin implementation because the design seems obvious. The plan is the
deliverable.

## Report

The plan file carries the observable goal, what the probe proved or falsified
with its numbers, and the pull-request sequence. In the self-contained reply,
give Gary the recommended design, the evidence that decides it, the exact
pull-request scope, and the question that needs his answer. Link the plan only
as supporting evidence. Do not record the plan's length, its phase count, the
size of the survey behind it, or a probe result that changes no decision.
