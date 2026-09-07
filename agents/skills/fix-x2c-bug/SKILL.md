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

Reproduce the defect, repair its cause, and verify the behavior the user sees.
An investigation-only request ends with the cause and recommended repair.

## Reproduce and trace

Read the relevant source, tests, and instructions. Reproduce at current `HEAD`
before editing, including findings from reviews or other agents. Reduce the
input to a useful deterministic example in `/tmp`; inspect its output,
diagnostic, exit status, or generated C as appropriate. If it does not
reproduce, investigate the relevant environment or version difference and
report the uncertainty instead of claiming a repair.

Use [the debugging guide](../../x2c-debugging-guide.md) for pipeline dumps,
progressive testing, module guidance, and crash investigation. Test suggested
causes with focused probes. Use an isolated clean checkout to distinguish a
pre-existing defect while preserving worktree edits.

For parser, AST, or transform work, consult
[the Match guide](../../replacing-manual-ast-walks-with-match.md). Reuse the
existing production and canonical AST operations.

## Repair and verify

Fix the cause with the smallest coherent change that preserves surrounding
behavior. Follow necessary work across modules; keep unrelated cleanup
separate. Apply root compatibility and validation rules.

Add regression coverage for the observable defect in the existing suites or
fixtures. Demonstrate that the reproduction and relevant regression checks
fail against the unfixed code and pass with the repair. Use enough cases to
cover distinct affected behavior; test count and patch size are not targets.
Prefer actual diagnostics and runtime behavior when those are what failed;
inspect generated C or ABI details when they are the relevant behavior.

Remove temporary instrumentation. Review and fix the completed authored diff,
then follow root validation and publication instructions. Routine authorized
repairs deliver to `main`; requested PRs retain review.

For an investigation, report the reproduced cause, consequence, and proposed
repair without edits. For a completed fix, report the changed behavior and the
before/after verification. Name any unreproduced or unresolved behavior.
