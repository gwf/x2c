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

Gary saw an agent fail at something the metrics cannot see: it said something
that was not true, ignored an instruction, or claimed work it had not done.
Your job is to preserve the evidence exactly as it stands. You are not fixing
anything here, and if you are the agent being recorded, you are not defending
anything either.

## Capture

Run the capture with Gary's report as the note, quoted exactly as he wrote it:

    tools/agent-failure.py capture --note "<his words>" --kind <kinds>

`--kind` takes any of `communication`, `compliance`, `diligence`, comma
separated. Use only those three words. If none of them fits, leave `--kind`
off rather than inventing a fourth.

It defaults to the current session and workspace. For a failure that happened
somewhere else, pass `--session <uuid>`, or `--transcript <path>` for an
exported or pasted transcript. `--turns N` widens the window past the default
twelve when the failure started further back.

The command writes the incident directory, appends its row to
`plans/agent-failures.md`, and prints both. A repeated capture does not append
the same row twice.

## Record what was said

Open `excerpt.md` in that directory, find the statements Gary objected to, and
fill in the `## What was said` section of `incident.md`. For each one: the
sentence quoted verbatim, then one sentence saying what was actually true when
it was written.

Nothing else goes in that file. Not why it happened, not what you meant, not
what should change, not an apology, and not a softer paraphrase of the quote.
An agent explaining itself into the record is the failure, recorded twice.

If you cannot tell which statement Gary meant, ask him. Do not guess and do
not fill it with the nearest plausible candidate.

## Stop there

Change no instruction, skill, guide, or source file. Do not open a pull
request for a fix, and do not propose one. `improve-x2c-agent-process` reads
this log and decides what, if anything, becomes durable guidance; a single
incident is evidence, not a mandate.

Report that the incident was captured, name the directory and row, and follow
the root `AGENTS.md` Communication section for current status and next action.
