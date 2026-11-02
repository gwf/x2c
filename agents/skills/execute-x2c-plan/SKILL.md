---
name: execute-x2c-plan
description: >-
  Carry out one already-decided x2c change and deliver it. Use when a plan,
  specification, or request records the decisions and the remaining work is
  to implement, validate, and publish, including feature, integration, example,
  and documentation work. Do not use to decide a design; use plan-x2c-change.
  Do not use to diagnose a defect; use fix-x2c-bug.
---

# Execute an x2c plan

Implement the whole decided change, verify the resulting behavior, and deliver
it under the root [AGENTS.md](../../../AGENTS.md) publication instructions.

## Read and review the request

Read the named plan or specification, nearest instructions, current source,
tests, and a relevant working example. For one change in a sequence, inspect
the preceding diff for conventions and affected artifacts. Language and
library changes also use the current book pages and `docs/AGENTS.md`.

Check settled decisions against the source and the design review described in
[plans/README.md](../../../plans/README.md). Complete a missing review yourself
within the authorized implementation. Resolve routine implementation choices
from existing code. Ask only when a consequential choice remains unresolved or
the requested design would change compatibility beyond the request.

## Implement and verify

Edit authoritative sources and follow the connected changes through callers,
tests, and documentation.

Use focused checks to answer implementation questions and verify what the user
will observe. Refresh affected symbols, headers, fixtures, and generated docs
through their documented targets, accepting only reviewed output changes. The
[root work policy](../../../AGENTS.md#work-in-the-repository) owns local
bootstrap transitions and checkpoint commits. Inspect generated changes
against the authored changes that explain them.

## Deliver

Follow the root delivery selection: submit a ready PR with focused evidence
to the shared integrator by default. The integrator owns broad checks and
publication. Subordinate workers give private handoffs to their orchestrator.
Review-held PRs and local-only requests retain their boundaries.
The work is complete when the requested behavior works and the authorized
delivery is verified. Production promotion and advancement of `main` require
Gary's separate release authorization. Report whether the result was published,
submitted, or retained locally, its verification, and any remaining limitation.
