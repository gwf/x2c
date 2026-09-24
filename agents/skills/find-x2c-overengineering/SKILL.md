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
program. Public APIs without in-tree callers are not evidence of waste. Treat
mechanical scores as a queue, not a verdict.

## Start or resume the cumulative audit

From the repository root, run:

```sh
python3 agents/skills/find-x2c-overengineering/scripts/overengineering.py scan
```

The command inventories current `src/` and hand-authored `lib/`, selects at
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

Before presenting a candidate to Gary, lead with the user-visible or developer-
visible capability that removal would lose and show one small concrete example.
Then give the removable machinery and size. If removal intentionally drops a
working capability and Gary has not said that capability is unwanted, the
candidate is `open` pending that product decision, never `confirmed` merely
because it has no current in-tree adopter.

Use these statuses only: `open`, `confirmed`, `rejected`, `superseded`, and
`removed`. Deleted historical examples are calibration, never live candidates.
Mark a row stale when its recorded source digest differs from the current
region; do not preserve an old verdict across changed code without review.

## Apply the hard exclusions

- Inspect only `src/**/*.x` and hand-authored `lib/**/*.x`; exclude
  `lib/x2c.x`, examples, packages, tools, tests, generated files, and modules.
- Do not penalize a public API for having no repository consumer.
- Do not treat an intentionally open or documented capability as waste because
  current `src/` and `lib/` do not exercise it.
- A test written for machinery is evidence of its behavior, not an independent
  production requirement.
- Prefer private duplicate facts, replay/reconciliation, registries, ledgers,
  derived state, parallel analysis, and bookkeeping whose deletion removes a
  connected mechanism.
- Separate direct session evidence from inference. Flag review becoming
  implementation, post-hoc plan expansion, and an edge case becoming an
  unbounded completeness obligation.
- Never edit production source or begin a deletion. Use
  `investigate-x2c-overengineering` for one uncertain candidate and
  `simplify-x2c-source` only after Gary authorizes removal.

## Trace a known deletion for calibration

```sh
python3 agents/skills/find-x2c-overengineering/scripts/overengineering.py \
  trace-deletion COMMIT
```

This attributes deleted parent-side ranges, including deleted files and
replacement hunks. Blame proves last-line provenance, not conceptual origin;
squashes remain provenance walls. Keep restored iterator, error-record, and
source-map deletions as negative controls rather than proof of overengineering.
