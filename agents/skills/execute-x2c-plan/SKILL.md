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
tests, and documentation. For parser, AST, or transform work, use
[the Match guide](../../replacing-manual-ast-walks-with-match.md): reuse the
recursive-descent production, bind canonical fields with source patterns, and
return rewritten ASTs with visible templates.

Use focused checks to answer implementation questions and verify what the user
will observe. Refresh affected symbols, headers, fixtures, and generated docs
through their documented targets, accepting only reviewed output changes. Let
the root publication command perform the final bootstrap refresh and build
sequence unless a staged language transition needs an earlier build.

Before publication validation, review and fix the completed authored diff.
Look for deletion and reuse opportunities, repeated checks of established
facts, unnecessary machinery, and code that could use x2c more directly.
Inspect generated changes against the authored changes that explain them.

## Deliver

Follow root validation and publication instructions on the final tree. Routine
implementation delivers to `main`; use a PR when requested. The work is
complete when the requested behavior works and the authorized delivery is
verified. Report the behavior delivered, validation result, and any remaining
limitation plainly.
