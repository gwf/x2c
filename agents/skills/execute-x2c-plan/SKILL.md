---
name: execute-x2c-plan
description: >-
  Carry out one already-decided x2c change and publish it. Use when a plan,
  specification, or request records the decisions and the remaining work is
  to implement, validate, and publish a single pull request, including
  feature, integration, example, and documentation work. Do not use to decide
  a design; use plan-x2c-change. Do not use to diagnose a defect; use
  fix-x2c-bug.
---

# Execute an x2c plan

Deliver one pull request from decisions someone already made. Treat the
plan's settled choices as settled, implement the whole coherent change, and
prove the final tree once.

## Load the decided plan

Read the named plan, the root `AGENTS.md`, and the source and tests the unit
touches. Identify the single unit you are executing and its boundary.

For a language or library semantics change, also read `docs/AGENTS.md` and the
current pages under `docs/` that own the behavior. Update those pages in the
same coherent change; agent guidance links to them instead of restating their
semantics.

Before treating a recorded plan's choices as settled, confirm that it contains
the final review required by `plans/README.md` and that its claims about
current producers and reuse still match the source. If the review is absent,
or a proposed validator has no concrete failure beyond an earlier or more
specific error, return the work to planning and stop. Do not silently perform
the missing review during implementation. A direct request or specification
need not contain that plan heading, but it remains subject to the root Hard
Rules.

Do not relitigate a decision that passed that review. If the plan is wrong,
say so and stop; that is a planning question, not an implementation one.

If the plan does not decide something you need, ask one specific question
rather than inventing an answer or surveying the repository.

## Read the previous change of the same shape

When executing one unit of a sequence, read the diff of the unit before it
with `git show`. The prior change carries the conventions, the artifact
churn, and the test shape this one needs. Sessions that do this ask no
questions; sessions that skip it rediscover the same conventions.

## Implement the whole coherent change

Edit the authoritative `.x` sources and the narrow tests and documentation
that prove the retained behavior. Follow connected work inside the unit's
boundary. Remove tests and documentation that exist only for machinery the
change deletes.

For parser productions, AST consumers, or transforms, read
`agents/replacing-manual-ast-walks-with-match.md` before editing. Reuse the
owning recursive-descent production, bind canonical AST fields with source
patterns, and return rewritten ASTs as visible templates.

Use focused commands while an uncertainty is live: one compile, one fixture,
one suite, one direct invocation. Finish the coherent source, test,
documentation, and artifact changes before running any broad gate.

## Refresh affected artifacts

Artifact drift is discovered during validation and costs a failed gate every
time it is found late. When the change touches symbols, headers, fixtures, or
generated documentation, refresh them in dependency order first:
`make sym-update`, then `make hdr-sync`, then `make doc-generate` and
`make doc-check`.

A source change to `src/` or `lib/` changes the bootstrap snapshot. Let the
root publication command own the final refresh and validation sequence. Use a
separate self-host build during development only when it answers a live
question or the task is an explicit staged language transition. Read every
resulting `bootstrap/` hunk as source evidence.

## Review the completed source

Before the publication proof, inspect the completed authored diff. Name the
facts its consumers rely on and remove checks that repeat facts already
established by their producers. Look again for code that can be deleted or
reused, new machinery that does not earn its keep, and choices that do not read
like idiomatic x2c. Fix what this review finds before running the broad proof;
the review is product work, not a report or another gate.

## Prove the tree once

Run the applicable publication proof from the root `AGENTS.md` once, on the
final tree. A genuinely documentation-only diff uses:

```sh
tools/gate-state.py ensure doc-check
```

A diff containing source, runtime, build, test, tool, executable-example, or
generated-artifact files uses:

```sh
tools/gate-state.py ensure agent-pr-check
```

The command reuses a valid result or runs and records the complete target. Do
not decompose that target into its parts and run them separately.

If the proof fails, isolate the cause with focused checks or by halving the
batch. Preserve the complete failure log under `debug/`, stop before
publishing, and report the failing command.

## Publish

Follow the root `AGENTS.md` "Agent PR Push" exactly. The workspace branch is
the push destination and `dev` is only the base.

## Report

Gary gets the behavior delivered and the exact validation command and result,
in the self-contained reply the root `AGENTS.md` Communication section
describes. The machinery reused or removed and any correction the plan needed
go in the pull request body. Test counts, generated output, and process work
are never the main result.
