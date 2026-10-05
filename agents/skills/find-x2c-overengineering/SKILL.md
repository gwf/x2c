---
name: find-x2c-overengineering
description: >-
  Run a bounded, cumulative forensic audit of current hand-authored x2c
  compiler and runtime source for private machinery that may be unnecessary or
  over-engineered. Use when asked to find live bloat, performative engineering,
  invented internal requirements, or promising deletion candidates in src/
  and lib/. This skill reports and records candidates; it never edits source.
---

# Find x2c overengineering

Find connected internal machinery whose removal may simplify the current
program. Apply PR-10 to public APIs and the standard's "Finding bad code"
section to mechanical scores.

Apply PR-2, PR-3, PR-4, PR-10, FA-7, and TE-2 in
[the standard](../../x2c-code-standard.md) when judging a candidate.

## Start or resume the cumulative audit

From the repository root, run:

```sh
make commands
agents/skills/find-x2c-overengineering/scripts/overengineering scan
```

The script reads the compiler's definitions of current `src/` and
hand-authored `lib/` and the structure rules of `x2c lint`, selects at
most five promising regions not already attempted at the same source digest,
and creates an immutable run beneath
`~/.codex/x2c-overengineering/<repository-id>/runs/`. It prints the run path.
Use `--budget N` only when the user asks for a different bound.

Read [the evidence schema](references/evidence.md), the selected functions or
types in full, their producers and production consumers, relevant tests and
documentation, `git blame`, introducing commits, and available session logs.
Review no more than the selected budget. Record every selection in the run's
`report.md`, including empty and refuted searches, so later runs can choose a
different target.

## Decide what belongs in the tracked ledger

Update `plans/overengineering-candidates.md` only for a source-reviewed live
candidate or a deliberate calibration case. A live row must name the current
file, function or type, exact lines, machinery, actual consumers, smallest
removal hypothesis, strongest keep case, provenance, confidence, and one next
proof. Do not put a mechanical hit in the ledger before reading its source.

Admit a live candidate only when it is an inward-facing abstraction without an
independent current purpose: a mirror, ledger, registry, replay layer,
reconciliation path, adapter round-trip, or derived state that callers can
bypass in favor of the real owner while preserving intended behavior. Before
presenting it, state the behavior that remains and the existing path that will
provide it. If removal disables a working capability, reject the hit before it
enters the live table. Low adoption never turns a feature into a candidate.

Use these statuses only: `open`, `confirmed`, `rejected`, `superseded`, and
`removed`. Deleted historical examples are calibration, never live candidates.
Mark a row stale when its recorded source digest differs from the current
region; do not preserve an old verdict across changed code without review.

## Apply the hard exclusions

- Inspect only `src/**/*.x` and hand-authored `lib/**/*.x`; exclude
  `lib/x2c.x`, examples, packages, tools, tests, generated files, and modules.
- Apply PR-10 to public operations, PR-2 and PR-3 to duplicate owners,
  and FA-7 to forwarding chains. Apply PR-4 and TE-2 to test evidence.
- Separate direct session evidence from inference. Flag review becoming
  implementation, post-hoc plan expansion, and an edge case becoming an
  unbounded completeness obligation.
- Never edit production source or begin a deletion. Use
  `investigate-x2c-overengineering` for one uncertain candidate and
  `simplify-x2c-source` only after Gary authorizes removal.

## Trace a known deletion for calibration

```sh
agents/skills/find-x2c-overengineering/scripts/overengineering \
  trace-deletion COMMIT
```

This attributes deleted parent-side ranges, including deleted files and
replacement hunks. Blame proves last-line provenance, not conceptual origin;
squashes remain provenance walls. Keep restored iterator, error-record, and
source-map deletions as negative controls rather than proof of overengineering.
