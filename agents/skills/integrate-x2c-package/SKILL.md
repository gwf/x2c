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

Identify the ordinary tasks a developer brings to this kind of library before
judging the existing wrapper. Build the task list from the library's purpose,
then check whether importing the package makes each task practical with x2c
values, without vendored headers or hand-written substitutes for missing
operations. Present an unresolved scope choice to Gary; follow an already
approved task list directly.

Use source and upstream documentation to form hypotheses, then prove task
reachability with actual programs. Inspect imported constants and raw options
before adding redundant convenience methods. For read-only assessment, build
copies under `/tmp` with the shared dependency cache. Exercise values as their
real consumer does: Lisp must be able to inspect values returned to it.

## Design around useful examples

Follow the package instructions for a short application and a broader one;
review the short example first. Working examples establish usability beyond
wrapped function counts. When a useful Lisp surface exists, provide it in the
package unit behind one public installer over ordinary Lisp values.

Use `plan-x2c-change` for unresolved compiler, runtime, or language design.
For an already decided package change, use `execute-x2c-plan` to complete the
implementation and authorized delivery.

## Verify and report

Run `make packages-check` for package implementation or completeness work;
a package's local test target covers less. Preserve the root rule that this
network-dependent check remains outside recurring publication gates.
For a narrower review, state the checks and task coverage actually examined.

Follow the current package acceptance rules; status changes remain Gary's
decision. Present the short application's real output, the broader example,
and evidence for each assessed task. Completion means the requested package
work or assessment is demonstrated, with remaining limitations stated.
