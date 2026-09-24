---
name: investigate-x2c-overengineering
description: >-
  Deeply adjudicate one current x2c src/ or lib/ overengineering candidate by
  tracing its behavior, consumers, ownership, history, and session provenance.
  Use after a bounded audit identifies a specific mechanism. This skill proves
  or rejects the candidate and records the result; it never removes source.
---

# Investigate one x2c overengineering candidate

Resolve one named row from `plans/overengineering-candidates.md` or one exact
region produced by `find-x2c-overengineering`. Do not broaden the assignment to
neighboring subsystems or implement a deletion.

Read [the adjudication checklist](references/adjudication.md). Trace the full
connected mechanism: producers, consumers, ownership and lifetime, errors,
side effects, generated output, tests, documentation, and history. When commit
provenance points to an agent session, inspect the raw session and distinguish
what it states from what the code history merely suggests.

Choose exactly one disposition:

- `confirmed`: an existing path preserves the required behavior and a
  connected mechanism can plausibly disappear;
- `rejected`: the machinery carries a distinct current obligation;
- `superseded`: current source no longer matches the recorded candidate;
- `removed`: the region is absent from the current tree; or
- `open`: one named, bounded proof is still missing.

Update the candidate row with exact current lines, evidence, the strongest
counterargument, confidence, and next proof. Add the investigation to the
originating external run's `report.md`, or create a small adjudication run with
the discovery script when the original run is unavailable.

A `confirmed` result is a recommendation, not authorization. Hand an approved
removal to `simplify-x2c-source`. Never edit `src/`, `lib/`, generated output,
tests, or documentation while using this skill.
