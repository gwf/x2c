---
name: integrate-x2c-package
description: >-
  Integrate a third-party C library as an x2c package, or judge whether an
  existing package is complete. Use when a library needs an ordinary x2c
  surface, when a package's reach must be measured against the tasks a
  developer actually brings to that kind of library, or when a package's
  examples, Lisp surface, or gate are in question. Do not use to decide a
  compiler, runtime, or language design; use plan-x2c-change. Do not use to
  land package work a plan already decided; use execute-x2c-plan.
---

# Integrate an x2c package

Give one C library a useful ordinary x2c surface, or assess its completeness.
[packages/AGENTS.md](../../../packages/AGENTS.md) owns current package status,
examples, acceptance, and package-local rules. Use those current instructions
rather than copying changing status into this skill.

## Start with developer tasks

Use the developer-task and surface rules in
[packages/AGENTS.md](../../../packages/AGENTS.md). Follow an approved task
list directly; present unresolved scope choices to Gary.

Use source and upstream documentation to form hypotheses, then prove task
reachability with actual programs. Inspect imported constants and raw options
before adding redundant convenience methods. For read-only assessment, build
copies under `/tmp` with the shared dependency cache. Exercise values as their
real consumer does: Lisp must be able to inspect values returned to it.

## Design around useful examples

The package instructions own the examples and Lisp surface requirements.

Use `plan-x2c-change` for unresolved compiler, runtime, or language design.
For an already decided package change, use `execute-x2c-plan` to complete the
implementation and authorized delivery.

## Verify and report

Verify implementations with the affected package's focused tests and examples.
For reviews, use focused probes when source leaves a concrete question open.
State the tasks and behavior examined. The integrator selects broader package
checks when a combined change affects package clients.

Follow the current package acceptance rules; status changes remain Gary's
decision. Present the short application's real output, the broader example,
and evidence for each assessed task. Completion means the requested package
work or assessment is demonstrated, with remaining limitations stated.
