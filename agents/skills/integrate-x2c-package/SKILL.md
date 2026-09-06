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

Bring one C library to an ordinary x2c surface, or judge whether a package
already there is finished. Read the root and package instructions first.
`packages/AGENTS.md` owns current package status, package-local rules, and
acceptance; this skill owns only the order of the work.

When the design is decided and recorded, hand the units to `execute-x2c-plan`
and follow it. When the open question is about the compiler, the runtime, or
the language rather than about this library's surface, that is
`plan-x2c-change`.

## Establish what the library is for

Follow the current status and comparison guidance in `packages/AGENTS.md`.
Do not copy package names, acceptance counts, or changing status into this
skill.

## Write the ordinary-task list before reading the client

Ten to fifteen tasks a working developer brings to this kind of library,
written down before you look at what the package provides. Then check each
row: reachable through the imported surface, with x2c values, no vendored
header, no hand-rolled loop over a lower operation.

The rows do not transfer between libraries. PCRE2's thirteen and yyjson's
eleven share no entry. The method transfers. The list is the deliverable Gary
approves or edits, and it is what "complete" means afterwards.

## Prove every row by probe

Never answer a row by reading. An audit of PCRE2 read the client and reported
caseless, multiline, and anchored matching as unreachable; a twelve-line probe
showed that `Regexp.compile` takes a raw options word and `import "pcre2"`
carries the `PCRE2_*` constants. Four redundant methods were nearly written.

Copy `packages/` to `/tmp`, build there against the same shared dependency
cache, and leave the worktree alone. Exercise every value the way its
destination will: a value a binding hands to Lisp must be one that Lisp can
take apart, not merely one the same path accepts back.

## Let the examples decide

Write the short application and the broader one before implementing, and show
Gary the short one first. `packages/AGENTS.md` "Begin with the examples" and
"Review the developer experience" govern. A package with no screen-sized path
is unfinished however many upstream functions it reaches, and a passing test
suite cannot rescue an awkward short example.

## Ship the Lisp surface inside the package

When the library has a useful value-oriented Lisp surface, it is in the
package unit behind one public installer, over values Lisp already operates
on. Bindings defined in an example reach nobody who imports the package.

## Leave it gated

Run `make packages-check` before reporting. A package's own `test` target does
not cover the complete package surface. The repository-wide target remains
optional; the root `AGENTS.md` "Process Ceiling" governs any move to make it
mandatory.

## Stop at acceptance

A package's current acceptance rule and status are in `packages/AGENTS.md`.
Present the short application and its real output, then the broader one. Do
not change package status yourself.

## Report

In the self-contained reply the root `AGENTS.md` Communication section
describes, Gary gets the current result, the task list with a verdict on every
row, the probe output behind any row called reachable, and the short
application first. Wrapped function counts, declaration inventories, and test
counts are never the main result.
