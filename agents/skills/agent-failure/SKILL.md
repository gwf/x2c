---
name: agent-failure
description: >-
  Record a reported failure in agent communication, compliance, or diligence,
  with evidence captured from the session it happened in. Gary invokes this
  himself when he sees one; never select it, and never invoke it to report
  your own conduct unprompted.
disable-model-invocation: true
---

# Record a reported agent failure

Use only when Gary explicitly invokes it. Preserve his report and the relevant
session evidence without changing agent guidance or product code.

## Capture

Run the capture with Gary's exact words as the note, using shell-safe quoting:

```sh
tools/agent-failure.py capture --note '<his words>' --kind <kinds>
```

`--kind` accepts `communication`, `compliance`, and `diligence`, comma
separated. Omit it if none fits. The default is the current session and
workspace; use `--session <uuid>` for another session or `--transcript <path>`
for an exported transcript. `--turns N` widens the default twelve-turn window.

The command writes the incident directory, appends its row to
`plans/agent-failures.md`, and prints both. Repeating a capture does not append
the same row twice.

## Record the statements

Read the captured `excerpt.md` and fill in `## What was said` in `incident.md`.
For each statement Gary objected to, quote the sentence verbatim and state what
was actually true when it was written. Keep explanations of intent, proposed
fixes, and apologies outside this evidence record. Ask if the disputed
statement cannot be identified.

Completion is the captured incident, its exact statements, and its index row.
Report their location. A later dedicated `improve-x2c-agent-process` request
can evaluate changes; incident capture itself ends here.
