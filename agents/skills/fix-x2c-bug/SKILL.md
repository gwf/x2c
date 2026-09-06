---
name: fix-x2c-bug
description: >-
  Diagnose and repair a defect in the x2c compiler, runtime, build, or
  tooling. Use when something crashes, miscompiles, hangs, produces wrong
  output, regresses, or fails a test, including a defect inherited from a
  review finding or a bug report. Do not use to add or change behavior on
  purpose; use plan-x2c-change or execute-x2c-plan.
---

# Fix an x2c bug

Reproduce the defect, find its cause, make the smallest change that removes
the symptom, and pin it with one test. The repair is usually a few lines. Keep
everything around the repair that small too.

## Reproduce before anything else

Reproduce the defect at current `HEAD` before editing anything. If it does not
reproduce, say so and stop. Do not fix a bug you cannot demonstrate.

This applies with full force to a defect you inherited. A finding from a
review, a catalog, a plan row, or another agent is a claim, not a fact, and
findings produced without running the compiler are frequently wrong. A
severity label does not make a claim true. Reproducing costs a few tool calls;
building on a false premise has cost this project hours and shipped
regressions.

Reduce the reproduction until it is small and deterministic. Write it under
`/tmp`, translate it, and read the observable result: the generated C, the
diagnostic, the exit status, the printed output. An external oracle is worth
finding when one exists, such as compiling the generated C with `cc` and
reading its warnings.

## Find the cause with the compiler's own instruments

`agents/x2c-debugging-guide.md` owns this. Read it. It lists the dump flags
that short-circuit the pipeline, the progressive-testing pattern, and the
common pitfalls with their owning modules.

When the defect is in a parser production, AST consumer, or transform, also
read `agents/replacing-manual-ast-walks-with-match.md` before editing. Reuse
the owning recursive-descent production and canonical AST patterns instead of
adding another token scan or positional walk.

Prefer measurement over theory. Bisect the input rather than reasoning about
it; `git stash` with a pristine rebuild proves whether a defect is
pre-existing; `git show <sha>~1:<file>` shows what a shape looked like before.
Use `lldb` when the failure is a crash or a stack question.

When a hypothesis is cheap to test, test it before building on it. Do not
implement a design that assumes an untested cause. Treat a suggested cause,
including one from the user, as a hypothesis to measure rather than a
conclusion to act on; state plainly when measurement contradicts it.

If the user asked only for investigation or diagnosis, stop here. Report the
reproduced cause, consequence, and recommended repair without editing the
worktree. Continue only when the user authorized a fix.

## Make the smallest fix

Fix the cause, at its owner, with the smallest change that makes the symptom
go away. Show the before-and-after receipt: the same reproduction, the old
observable result, the new one.

Do not bundle unrelated cleanup, and do not widen the fix to cover shapes you
have not seen fail.

## Pin the fix with a check you have seen fail

Add one test that covers the observable defect, in the existing suite or as a
compiler fixture. Then take the fix away and run it. A check you have only
ever seen pass proves nothing, because a check that never reaches the failing
path looks exactly like a check that passes.

This governs everything you treat as evidence, not only a committed test. If a
probe, an assertion, a comparison, or a throwaway script is the reason you
believe the repair works, run it once against the unfixed code and watch it
fail before you trust it. A check written after the fix, from the same
understanding that produced the fix, confirms that understanding whether or
not it was right.

Test what the user sees. A `.stdout` fixture that captures the wrong behavior
is the right pin. Pinning generated C, gensym numbering, or internal structure
adds a file that must be rebaselined by every future change and proves less.

## Keep the repair small around the edges

The fixes in this repository are small and sound. What inflates is everything
surrounding them. Specifically, do not:

- write a plan document, a phase structure, or a task ledger for a repair;
- dispatch a subagent for a change you can make yourself, or fan out review
  agents over a defect you have already root-caused;
- build a permanent gate, probe script, Make target, or CLI flag out of one
  episode, and never wire one into `precommit`, `check`, or `agent-pr-check`;
- add defensive checks, back-pointers, or cleanup branches beyond the cause;
- leave diagnostic instrumentation in the tree. Instrument in `/tmp` or behind
  a temporary edit and revert it. Never relabel temporary instrumentation as a
  feature to justify keeping it.

The root `AGENTS.md` "Process Ceiling" governs anything recurring. A defect is
not authorization to add process.

## Report

Report a defect the way you would want one reported: what is broken, what
you recommend, and a request to proceed. Do not bury it in a menu of options
and do not present it as an emergency. For a fix, Gary gets the cause in one
sentence and the fix in one sentence; the receipt and the regression test
with its red-then-green result go in the pull request body.
